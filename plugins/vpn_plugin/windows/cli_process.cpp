#include "cli_process.h"

#include "cli_output.h"

#include <array>
#include <cstdio>

namespace vpn_plugin {

namespace {

using cli_output::ParseState;

std::string Now() {
    SYSTEMTIME t;
    GetLocalTime(&t);
    char buf[32];
    snprintf(buf, sizeof(buf), "%04u-%02u-%02uT%02u:%02u:%02u.%03u", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute,
            t.wSecond, t.wMilliseconds);
    return buf;
}

std::wstring Quote(const std::filesystem::path& path) { return L"\"" + path.wstring() + L"\""; }

std::string LastErrorText(const char* what) { return std::string(what) + " failed, error " + std::to_string(GetLastError()); }

/**
 * Ctrl+C is the CLI's clean shutdown (routes, DNS, kill switch). Delivering
 * it means attaching to the CLI's hidden console, and every process attached
 * receives the event - attaching the app itself closed it. So a short-lived
 * copy of the app does it: `cattunnel.exe --send-ctrl-c <pid>` (see
 * windows/runner/main.cpp). It is elevated like the app, as the CLI is.
 */
bool SendCtrlC(DWORD pid) {
    std::wstring exe(MAX_PATH, L'\0');
    DWORD len = GetModuleFileNameW(nullptr, exe.data(), static_cast<DWORD>(exe.size()));
    if (len == 0 || len == exe.size()) return false;
    exe.resize(len);

    std::wstring command_line = L"\"" + exe + L"\" --send-ctrl-c " + std::to_wstring(pid);
    STARTUPINFOW startup = {sizeof(startup)};
    PROCESS_INFORMATION helper = {};
    if (!CreateProcessW(exe.c_str(), command_line.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr,
                nullptr, &startup, &helper)) {
        return false;
    }
    CloseHandle(helper.hThread);
    DWORD exit_code = 1;
    if (WaitForSingleObject(helper.hProcess, 5000) == WAIT_OBJECT_0) {
        GetExitCodeProcess(helper.hProcess, &exit_code);
    } else {
        TerminateProcess(helper.hProcess, 1);
    }
    CloseHandle(helper.hProcess);
    return exit_code == 0;
}

}  // namespace

CliProcess::CliProcess(std::filesystem::path log_path, StateCallback on_state)
    : m_log_path(std::move(log_path)), m_on_state(std::move(on_state)) {}

CliProcess::~CliProcess() { Stop(); }

std::optional<std::string> CliProcess::Start(const std::filesystem::path& exe,
        const std::filesystem::path& config_path, const std::string& log_level) {
    Stop();

    std::lock_guard lock(m_mutex);

    SECURITY_ATTRIBUTES inheritable = {sizeof(inheritable), nullptr, TRUE};
    HANDLE read_end = nullptr;
    HANDLE write_end = nullptr;
    if (!CreatePipe(&read_end, &write_end, &inheritable, 0)) return LastErrorText("CreatePipe");
    SetHandleInformation(read_end, HANDLE_FLAG_INHERIT, 0);

    // Only the pipe is inherited, not whatever else the app has open.
    SIZE_T attr_size = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &attr_size);
    std::vector<char> attr_buffer(attr_size);
    auto* attrs = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(attr_buffer.data());
    if (!InitializeProcThreadAttributeList(attrs, 1, 0, &attr_size) ||
            !UpdateProcThreadAttribute(attrs, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, &write_end, sizeof(write_end),
                    nullptr, nullptr)) {
        std::string error = LastErrorText("ProcThreadAttributeList");
        CloseHandle(read_end);
        CloseHandle(write_end);
        return error;
    }

    STARTUPINFOEXW startup = {};
    startup.StartupInfo.cb = sizeof(startup);
    // A hidden console of its own rather than CREATE_NO_WINDOW: without a
    // console there is nothing to AttachConsole to, and Ctrl+C (the clean
    // shutdown) can't be delivered.
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.StartupInfo.wShowWindow = SW_HIDE;
    startup.StartupInfo.hStdOutput = write_end;
    startup.StartupInfo.hStdError = write_end;
    startup.lpAttributeList = attrs;

    std::wstring command_line = Quote(exe) + L" -c " + Quote(config_path) + L" -l " +
            std::wstring(log_level.begin(), log_level.end());
    PROCESS_INFORMATION process = {};
    BOOL created = CreateProcessW(exe.c_str(), command_line.data(), nullptr, nullptr, TRUE,
            CREATE_SUSPENDED | CREATE_NEW_CONSOLE | EXTENDED_STARTUPINFO_PRESENT, nullptr,
            exe.parent_path().c_str(), &startup.StartupInfo, &process);
    std::string create_error = created ? "" : LastErrorText("CreateProcessW");
    DeleteProcThreadAttributeList(attrs);
    CloseHandle(write_end);  // the child has its copy; EOF on read_end = child gone
    if (!created) {
        CloseHandle(read_end);
        return create_error;
    }

    m_job = CreateJobObjectW(nullptr, nullptr);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (m_job == nullptr ||
            !SetInformationJobObject(m_job, JobObjectExtendedLimitInformation, &limits, sizeof(limits)) ||
            !AssignProcessToJobObject(m_job, process.hProcess)) {
        std::string error = LastErrorText("job object");
        TerminateProcess(process.hProcess, 1);
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        CloseHandle(read_end);
        if (m_job) CloseHandle(m_job);
        m_job = nullptr;
        return error;
    }

    ResumeThread(process.hThread);
    CloseHandle(process.hThread);
    m_process = process.hProcess;
    m_pid = process.dwProcessId;

    AppendLog("=== CatTunnel: starting " + exe.filename().string() + " (pid " + std::to_string(m_pid) + ") ===");

    HANDLE reader_process = nullptr;
    DuplicateHandle(GetCurrentProcess(), m_process, GetCurrentProcess(), &reader_process, 0, FALSE,
            DUPLICATE_SAME_ACCESS);
    m_reader = std::thread(&CliProcess::ReadOutput, this, read_end, reader_process, config_path);
    return std::nullopt;
}

void CliProcess::Stop(DWORD timeout_ms) {
    std::unique_lock lock(m_mutex);
    if (m_process == nullptr) return;

    if (WaitForSingleObject(m_process, 0) == WAIT_TIMEOUT) {
        if (!SendCtrlC(m_pid) || WaitForSingleObject(m_process, timeout_ms) == WAIT_TIMEOUT) {
            AppendLog("=== CatTunnel: the client didn't stop in time, terminating ===");
            TerminateProcess(m_process, 1);
            WaitForSingleObject(m_process, timeout_ms);
        }
    }

    JoinReader();
    CloseHandle(m_process);
    CloseHandle(m_job);
    m_process = nullptr;
    m_job = nullptr;
    m_pid = 0;
}

bool CliProcess::IsRunning() {
    std::lock_guard lock(m_mutex);
    return m_process != nullptr && WaitForSingleObject(m_process, 0) == WAIT_TIMEOUT;
}

void CliProcess::JoinReader() {
    if (m_reader.joinable()) m_reader.join();
}

void CliProcess::ReadOutput(HANDLE pipe, HANDLE process, std::filesystem::path config_path) {
    bool config_deleted = false;
    std::string pending;
    std::array<char, 4096> buffer;
    DWORD read = 0;
    while (ReadFile(pipe, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr) && read > 0) {
        pending.append(buffer.data(), read);
        size_t newline;
        while ((newline = pending.find('\n')) != std::string::npos) {
            std::string line = pending.substr(0, newline);
            pending.erase(0, newline + 1);
            if (!line.empty() && line.back() == '\r') line.pop_back();
            HandleLine(line, config_deleted, config_path);
        }
    }
    if (!pending.empty()) HandleLine(pending, config_deleted, config_path);
    CloseHandle(pipe);

    WaitForSingleObject(process, INFINITE);
    DWORD exit_code = 0;
    GetExitCodeProcess(process, &exit_code);
    CloseHandle(process);
    AppendLog("=== CatTunnel: the client exited with code " + std::to_string(exit_code) + " ===");

    if (!config_deleted) {
        std::error_code ignored;
        std::filesystem::remove(config_path, ignored);
    }
    m_on_state(State::kDisconnected);
}

void CliProcess::HandleLine(const std::string& line, bool& config_deleted, const std::filesystem::path& config_path) {
    AppendLog(line);
    std::optional<State> state = ParseState(line);
    if (!state) return;

    // The CLI parses its config once, before connecting: the first state
    // line means the password file isn't needed any more.
    if (!config_deleted) {
        std::error_code ignored;
        std::filesystem::remove(config_path, ignored);
        config_deleted = true;
    }
    m_on_state(*state);
}

void CliProcess::AppendLog(const std::string& line) {
    std::lock_guard lock(m_log_mutex);
    std::error_code ec;
    if (m_log.is_open() && std::filesystem::file_size(m_log_path, ec) > kMaxLogBytes && !ec) {
        m_log.close();
        std::filesystem::path previous = m_log_path;
        previous += L".1";
        std::filesystem::remove(previous, ec);
        std::filesystem::rename(m_log_path, previous, ec);
    }
    if (!m_log.is_open()) {
        std::filesystem::create_directories(m_log_path.parent_path(), ec);
        m_log.open(m_log_path, std::ios::binary | std::ios::app);
    }
    // Records are separated by 0x1E only: a newline would end up in the
    // message or in front of the next timestamp.
    m_log << cli_output::ToRecord(line, Now()) << '\x1E';
    m_log.flush();
}

std::vector<std::filesystem::path> CliProcess::LogFiles() const {
    std::filesystem::path previous = m_log_path;
    previous += L".1";
    std::vector<std::filesystem::path> files;
    std::error_code ec;
    for (const auto& path : {previous, m_log_path}) {
        if (std::filesystem::exists(path, ec)) files.push_back(path);
    }
    return files;
}

void CliProcess::ClearLogs() {
    std::lock_guard lock(m_log_mutex);
    m_log.close();
    std::filesystem::path previous = m_log_path;
    previous += L".1";
    std::error_code ec;
    std::filesystem::remove(m_log_path, ec);
    std::filesystem::remove(previous, ec);
}

}  // namespace vpn_plugin

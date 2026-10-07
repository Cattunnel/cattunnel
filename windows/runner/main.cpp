#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <cwchar>

#include "flutter_window.h"
#include "utils.h"

// `cattunnel.exe --send-ctrl-c <pid>`: used by vpn_plugin (CliProcess) to stop
// trusttunnel_client cleanly. Sending Ctrl+C means attaching to the client's
// console, and whoever is attached receives the event too - so a throwaway
// process does it instead of the app, which would be closed by it.
static bool RunSendCtrlCHelper(int* exit_code) {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return false;
  }
  const bool is_helper = argc == 3 && wcscmp(argv[1], L"--send-ctrl-c") == 0;
  if (is_helper) {
    const DWORD pid = static_cast<DWORD>(wcstoul(argv[2], nullptr, 10));
    *exit_code = 1;
    ::FreeConsole();
    if (pid != 0 && ::AttachConsole(pid)) {
      ::SetConsoleCtrlHandler(nullptr, TRUE);
      *exit_code = ::GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0) ? 0 : 1;
      ::FreeConsole();
    }
  }
  ::LocalFree(argv);
  return is_helper;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  int helper_exit_code = 0;
  if (RunSendCtrlCHelper(&helper_exit_code)) {
    return helper_exit_code;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // 16:10, centered in the primary work area (logical px, like Create()).
  Win32Window::Size size(1120, 700);
  RECT work = {};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  const double scale = GetDpiForSystem() / 96.0;
  const int work_width = static_cast<int>((work.right - work.left) / scale);
  const int work_height = static_cast<int>((work.bottom - work.top) / scale);
  if (work_width > 0 && work_height > 0) {
    size = Win32Window::Size((std::min)(size.width, static_cast<unsigned int>(work_width * 9 / 10)),
                             (std::min)(size.height, static_cast<unsigned int>(work_height * 9 / 10)));
  }
  Win32Window::Point origin(
      static_cast<unsigned int>((std::max)(0, static_cast<int>(work.left / scale) + (work_width - static_cast<int>(size.width)) / 2)),
      static_cast<unsigned int>((std::max)(0, static_cast<int>(work.top / scale) + (work_height - static_cast<int>(size.height)) / 2)));
  if (!window.Create(L"CatTunnel", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

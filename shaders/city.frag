#version 460 core
// City pop v2: мы внутри города. Один проход, только float-uniform, без текстур.
// uPass 0: небо, вода, мокрый асфальт, тротуары (низ слоя сцены).
// uPass 1: плёночная плёнка поверх всего (зерно, виньетка, засвет); вывод премультиплицированный.
// Здания, вывески, машины, люди, самолёт рисует Canvas 2D (во Flutter CustomPainter) между проходами.
precision highp float;
#include <flutter/runtime_effect.glsl>

layout(location = 0) uniform float uTime;       // секунды
layout(location = 1) uniform vec2  uSize;       // размер в пикселях
layout(location = 2) uniform float uState;      // 0 город спит, 1 живёт полностью
layout(location = 3) uniform float uTraffic;    // 0..1 плотность огней движения на асфальте
layout(location = 4) uniform float uTimeOfDay;  // 0 день, 0.5 закат, 1 ночь
layout(location = 5) uniform float uDim;        // 0..1 сбой: часть города во тьме
layout(location = 6) uniform float uHorizon;    // горизонт сверху, доля высоты (0.40)
layout(location = 7) uniform float uPass;       // 0 сцена, 1 плёнка
layout(location = 8) uniform float uGrade;      // 1 обработка включена, 0 выключена (для сравнения)

layout(location = 0) out vec4 fragColor;

const float VPX   = 0.46;   // точка схода по x (доля ширины)
const float KERB  = 0.4;    // край проезжей части, м
const float QUAY  = 1.8;    // кромка набережной (парапет), м
const float QW    = 1.9;    // ширина спуска со ступенями до воды, м (city_buildings.dart: те же числа)
const float ROADL = -5.4;   // левый край проезжей части, м

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec3 neon(float h) {
  if (h < 0.3) return vec3(1.00, 0.28, 0.66);
  if (h < 0.55) return vec3(0.28, 0.92, 0.96);
  if (h < 0.8) return vec3(1.00, 0.70, 0.34);
  return vec3(0.62, 0.40, 1.00);
}
// три ключа: день, закат, ночь
vec3 P3(vec3 d, vec3 s, vec3 n, float t) {
  return t < 0.5 ? mix(d, s, t * 2.0) : mix(s, n, (t - 0.5) * 2.0);
}


// ======================= плёночная обработка (отдельный блок) =======================
// Одна функция: во Flutter её можно взять как второй шейдер-постпроцесс над слоем CustomPainter
// (ImageFilter.shader со sampler2D) или применять к цветам палитры. Трактовка негативной плёнки:
// мягкая S-кривая, поднятые тени, бирюзовые тени, тёплые света, сжатие светлого,
// насыщенность x0.91 (и немного меньше от «негатива»), баланс белого в тепло и чуть в зелень.
vec3 filmGrade(vec3 c, vec2 uv, float s) {
  c *= mix(vec3(1.0), vec3(1.10, 1.01, 0.86), s);                 // баланс белого: тепло +, зелень чуть
  float y = dot(c, vec3(0.299, 0.587, 0.114));
  float yc = y > 0.68 ? 0.68 + (y - 0.68) * (1.0 - 0.38 * s) : y; // подсветка: светлые сжимаются
  c *= yc / max(y, 1e-4);
  c = mix(c, c * c * (3.0 - 2.0 * c), 0.30 * s);                   // мягкая S-кривая
  c = mix(c, vec3(0.09) + c * 0.91, 0.55 + 0.35 * s);               // тень +30: молочный чёрный ~0.09
  float l = dot(c, vec3(0.299, 0.587, 0.114));
  c = mix(vec3(l), c, 1.0 - 0.17 * s);                              // цвет: x0.91 и приглушение негатива
  float sh = (1.0 - smoothstep(0.0, 0.55, l)) * 0.50 * s;           // оттенок: тени к бирюзе (#2f6f6a)
  c = mix(c, c * 0.55 + vec3(0.184, 0.435, 0.416) * 0.62, sh);
  c += smoothstep(0.50, 1.0, l) * vec3(0.055, 0.028, -0.030) * s;   // света к тёплому
  float vg = length(uv - vec2(0.5, 0.52));                          // виньетка +10, лёгкая
  c *= 1.0 - 0.14 * s * vg * vg * 2.0;
  return c;
}

void main() {
  vec2 fc = FlutterFragCoord();
  vec2 uv = fc / uSize;
  float W = uSize.x;
  float H = uSize.y;
  float U = W / 360.0;
  float tod = clamp(uTimeOfDay, 0.0, 1.0);
  float night = smoothstep(0.45, 1.0, tod);
  float dayK = 1.0 - smoothstep(0.0, 0.5, tod);

  // ================= проход 1: зерно, засвет, виньетка поверх всего =================
  if (uPass > 0.5) {
    float sg = uGrade * P3(vec3(1.0), vec3(0.7), vec3(0.4), tod).x;   // сила: день 1, закат 0.7, ночь 0.4
    // The grain is fixed: it used to jump 12 times a second, which read as
    // a ripple running over the whole frame by day (owner 01.11, item 16).
    float gs = 2.0 * U;                                              // крупное зерно ~2 px
    vec2 gp = floor(fc / gs);
    float g = fract(sin(dot(gp, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    float grainAmt = 0.05 * (0.35 + 0.65 * sg);
    float leak = exp(-uv.x * 3.2) * (0.35 + 0.65 * smoothstep(0.1, 0.55, uv.y)) * (0.4 + 0.6 * vnoise(vec2(uv.y * 3.0, uTime * 0.05)));
    float leakAmt = uGrade * (dayK * 0.30 + smoothstep(0.0, 0.5, tod) * (1.0 - smoothstep(0.5, 0.8, tod)) * 0.12);
    vec3 add = leak * leakAmt * vec3(1.00, 0.62, 0.34);
    add += vec3(max(g, 0.0) * grainAmt * 2.0);
    float a = clamp(max(-g, 0.0) * grainAmt * 2.0, 0.0, 0.9);
    fragColor = vec4(add, a);
    return;
  }

  // ================= проход 0: сцена =================
  float hy = uHorizon * H;
  float k = 0.05 * H;
  vec3 col;

  // ---------- небо ----------
  vec3 zen = P3(vec3(0.55, 0.78, 0.88), vec3(0.24, 0.13, 0.46), vec3(0.025, 0.02, 0.11), tod);
  vec3 mid = P3(vec3(0.93, 0.82, 0.76), vec3(0.80, 0.28, 0.56), vec3(0.15, 0.05, 0.32), tod);
  vec3 hor = P3(vec3(1.00, 0.88, 0.66), vec3(1.00, 0.52, 0.38), vec3(0.88, 0.22, 0.52), tod);
  float t = clamp((hy - fc.y) / hy, 0.0, 1.0);
  vec3 sky = mix(hor, mid, smoothstep(0.0, 0.40, t));
  sky = mix(sky, zen, smoothstep(0.25, 1.0, t));
  sky += night * exp(-t * 5.0) * 0.20 * hor * (0.4 + 0.6 * uState);

  // солнце (полосатое, как в v1) снижается к закату, потом луна
  vec2 sunC = vec2(0.78 * W, hy - mix(0.13 * H, -0.06 * H, smoothstep(0.0, 0.62, tod)));
  float sR = 0.085 * W;
  float dS = length(fc - sunC);
  float sunV = 1.0 - smoothstep(0.55, 0.72, tod);
  float v = (sunC.y + sR - fc.y) / (2.0 * sR);   // 0 снизу диска
  float cutw = clamp((0.60 - v) * 1.4, 0.0, 0.75);
  float slit = (1.0 - smoothstep(cutw - 0.05, cutw + 0.05, fract(v * 9.0))) * step(v, 0.6);
  vec3 sunCol = mix(vec3(1.0, 0.45, 0.45), vec3(1.0, 0.93, 0.70), clamp(v, 0.0, 1.0));
  sky += exp(-max(dS - sR, 0.0) / (0.20 * W)) * mix(vec3(1.0, 0.8, 0.5), vec3(1.0, 0.45, 0.4), tod * 2.0) * 0.45 * sunV;
  slit *= smoothstep(0.30, 0.55, tod);   // днём солнце гладкое, полосатое только на закате
  float sunMask = (1.0 - smoothstep(sR - 1.0, sR + 1.0, dS)) * (1.0 - slit) * sunV;
  sky = mix(sky, sunCol, sunMask);
  vec2 moonC = vec2(0.80 * W, hy - mix(-0.06 * H, 0.24 * H, smoothstep(0.62, 1.0, tod)));
  float mR = 0.045 * W;
  float dM = length(fc - moonC);
  float moonV = smoothstep(0.62, 1.0, tod);
  sky += exp(-max(dM - mR, 0.0) / (0.10 * W)) * vec3(1.0, 0.6, 0.9) * 0.22 * moonV;
  vec2 crescent = fc - moonC - vec2(mR * 0.45, -mR * 0.15);
  float moonMask = (1.0 - smoothstep(mR - 1.0, mR + 1.0, dM)) * (1.0 - (1.0 - smoothstep(mR * 0.92 - 1.0, mR * 0.92 + 1.0, length(crescent))) * 0.9) * moonV;
  sky = mix(sky, vec3(1.0, 0.90, 0.96), moonMask);
  // звёзды
  float cell = 18.0 * U;
  vec2 sid = floor(fc / cell);
  float sh = hash21(sid);
  vec2 sp = vec2(hash21(sid + 3.1), hash21(sid + 7.7)) * 0.8 + 0.1;
  float sd = length(fract(fc / cell) - sp) * cell / U;
  float star = step(0.90, sh) * (1.0 - smoothstep(0.2, 1.3, sd)) * (0.5 + 0.5 * sin(uTime * (1.0 + sh * 3.0) + sh * 60.0));
  sky += star * smoothstep(0.65, 1.0, tod) * smoothstep(0.15, 0.5, t) * vec3(1.0, 0.92, 1.0);
  // плоские облака-полосы
  for (int i = 0; i < 4; i++) {
    float fi = float(i);
    float cx = mod(fi * 0.41 + uTime * 0.003 * (1.0 + fi * 0.3) + 0.8, 1.6) - 0.8 + 0.5;
    float cy = hy * (0.55 - fi * 0.11);
    vec2 d = vec2((uv.x - cx) / (0.20 + 0.04 * fi), (fc.y - cy) / (0.011 * H));
    float m = 1.0 - smoothstep(0.5, 1.0, length(d));
    sky = mix(sky, mix(vec3(1.0, 0.92, 0.88), vec3(0.55, 0.20, 0.60), night), m * 0.5);
  }
  col = sky;

  // ---------- земля ----------
  if (fc.y >= hy) {
    float d = max((fc.y - hy) / (6.0 * k), 0.0005);
    float X = (fc.x - VPX * W) / (k * d);     // метры поперёк улицы
    float S = 1.0 / d;                          // «расстояние» вдоль улицы
    float lightK = mix(0.18, 1.0, smoothstep(0.1, 0.75, tod));   // вывески и фонари
    float fall = exp(-d * 1.1);

    if (X > QUAY + QW) {
      // ----- вода: днём спокойная с бликами, ночью с отражениями огней -----
      vec3 wDeep = P3(vec3(0.20, 0.52, 0.62), vec3(0.30, 0.14, 0.36), vec3(0.03, 0.025, 0.13), tod);
      vec3 wNear = P3(vec3(0.12, 0.38, 0.50), vec3(0.16, 0.07, 0.24), vec3(0.02, 0.015, 0.09), tod);
      col = mix(wDeep, wNear, smoothstep(0.0, 1.0, d));
      col = mix(col, hor * 0.95, exp(-d * 3.5) * 0.65);                 // отражение неба у горизонта
      float z = 1.0 / (d * 1.2 + 0.05);
      float wx = (fc.x - VPX * W) / W * z * 3.0 + uTime * 0.08;
      float wy = z * 2.0 - uTime * (0.25 + 0.2 * night);
      float wn = vnoise(vec2(wx * 0.4, wy * 3.0));
      float streak = smoothstep(0.55, 0.88, wn);
      col += streak * 0.07 * mix(vec3(1.0, 0.95, 0.8), vec3(1.0, 0.5, 0.9), night);
      // блики солнца днём: колонка под солнцем
      float sunRef = exp(-pow((fc.x - sunC.x) / (W * (0.03 + 0.12 * d)), 2.0)) * fall * sunV;
      col += sunRef * (0.25 + 0.9 * streak) * mix(vec3(1.0, 0.9, 0.6), vec3(1.0, 0.45, 0.45), tod * 2.0);
      float moonRef = exp(-pow((fc.x - moonC.x) / (W * (0.02 + 0.08 * d)), 2.0)) * fall * moonV;
      col += moonRef * (0.2 + 0.8 * streak) * vec3(0.95, 0.80, 1.0);
      // Reflections of the far shore's lights are drawn by Dart under the real
      // buildings (city_buildings.dart); random columns here did not match them.
      // The water lies below the pavement: dark shadow of the quay wall at its foot.
      float foot = exp(-(X - QUAY - QW) * 2.4);
      col = mix(col, col * 0.35 + wNear * 0.2, foot * 0.75);
    } else if (X > QUAY) {
      // ----- набережная: парапет сверху, три ступени вниз к воде, тень под ними
      vec3 sw = P3(vec3(0.84, 0.77, 0.72), vec3(0.52, 0.33, 0.52), vec3(0.11, 0.08, 0.22), tod);
      vec3 wet = P3(vec3(0.20, 0.42, 0.50), vec3(0.20, 0.10, 0.30), vec3(0.03, 0.025, 0.12), tod);
      float t = (X - QUAY) / QW;
      float cap = 1.0 - smoothstep(0.08, 0.13, t);                 // верх парапета, светлый
      float tt = clamp((t - 0.13) / 0.87, 0.0, 0.999) * 3.0;
      float si = floor(tt);
      float sf = fract(tt);
      col = mix(sw * (0.90 - 0.17 * si), wet, 0.22 * si + 0.1);   // каждая ступень ниже, темнее, мокрее
      col *= 1.0 - 0.45 * (1.0 - smoothstep(0.0, 0.16, sf));      // тень подступёнка под краем ступени
      col = mix(col, sw * 1.05, cap * 0.9);
      col *= 1.0 - 0.30 * smoothstep(0.55, 1.0, t);               // у воды темнее
    } else if (X > KERB || X < ROADL) {
      // ----- тротуар -----
      vec3 sw = P3(vec3(0.86, 0.78, 0.72), vec3(0.55, 0.35, 0.55), vec3(0.11, 0.08, 0.22), tod);
      float tile = step(0.06, fract(X * 0.8)) * step(0.06 * d * 0.0 + 0.04, fract(S * 0.9));
      col = sw * (0.9 + 0.1 * tile);
      col += night * 0.04 * neon(hash21(vec2(floor(X * 0.5), 2.0))) * lightK * uState * fall;
    } else {
      // ----- проезжая часть: мокрый асфальт -----
      vec3 as = P3(vec3(0.52, 0.50, 0.55), vec3(0.28, 0.17, 0.33), vec3(0.055, 0.045, 0.115), tod);
      col = as;
      // мокрое зеркало неба: сильнее вдали
      float puddle = smoothstep(0.42, 0.72, vnoise(vec2(X * 0.7, S * 0.5)));
      float wet = mix(0.12, 0.45, night) + 0.25 * puddle * night + 0.1 * puddle;
      col = mix(col, hor, wet * exp(-d * 1.6) * 0.8);
      // разметка: осевая пунктиром и зебра
      float dash = step(fract(S * 0.55), 0.5) * (1.0 - smoothstep(0.08, 0.12, abs(X + 1.9)));
      float zebra = step(2.45, S) * step(S, 3.1) * step(fract((X + 5.4) * 0.62), 0.5);
      col = mix(col, vec3(0.96, 0.94, 0.88), (dash * 0.55 + zebra * 0.82) * mix(0.9, 0.78, night));
      // отражения огней города и вывесок на асфальте
      float cx = floor(X * 1.4);
      float hc = hash21(vec2(cx, 15.0));
      float cityLit = (0.12 + 0.88 * uState) * (1.0 - 0.7 * uDim * smoothstep(-1.0, -5.0, X));
      float sTr = 0.25 + 0.75 * vnoise(vec2(cx * 2.7, S * 0.9 - uTime * 0.2));
      float in1 = step(0.42, hc) * (1.0 - smoothstep(0.30, 0.48, abs(fract(X * 1.4) - 0.5)));
      // Short wet patches, not columns down the whole road: those read as a
      // trail that never goes away (owner 01.11).
      float wetSpot = smoothstep(0.62, 0.85, vnoise(vec2(cx * 1.7, S * 2.2 - uTime * 0.15)));
      col += neon(hash21(vec2(cx, 8.0))) * in1 * sTr * wetSpot * exp(-d * 1.3) * smoothstep(0.03, 0.2, d) * cityLit * lightK * (0.15 + 0.85 * night) * 0.45 * (1.0 - zebra * 0.8);
      // Подсветки полос от фар здесь больше нет: она горела и без машин,
      // постоянным шлейфом. Каждая машина светит сама (city_world.dart).
      // днём блик солнца на мокрой дороге
      // uTraffic stays in use: an unused uniform may be dropped by the
      // compiler and shift the indices the Dart side writes to.
      col += dayK * (0.08 + 0.02 * uTraffic) * smoothstep(0.55, 0.9, vnoise(vec2(X * 0.5, S * 0.4 + 3.0))) * vec3(1.0, 0.9, 0.7);
    }
    // дымка вдали
    col = mix(col, hor, exp(-d * 9.0) * 0.55);
  }

  // сбой: небо тускнеет
  float lm = dot(col, vec3(0.299, 0.587, 0.114));
  col = mix(col, vec3(lm) * vec3(0.92, 0.9, 1.0), 0.45 * uDim);
  col *= 1.0 - 0.22 * uDim;
  col = filmGrade(col, uv, uGrade * P3(vec3(1.0), vec3(0.7), vec3(0.4), tod).x);

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}

import 'package:trusttunnel/feature/companion/domain/cat_owner_preferences.dart';

/// Marsik introduces himself simply - this is a rare easter egg
/// (see [catFullNameRevealLines]), not shown during [CatIntroDialog].
const catFullName = 'Марсанваль фон Протокольдбург';

/// Shown instead of a normal compliment with low probability on a day's
/// first pet only (see [CatPettingDialog._onPetStroke]) - rare on purpose,
/// mixing the full-name reveal with other small "fun fact" easter eggs.
const catRareFacts = <String>[
  'Кстати... моё полное имя — Марсанваль фон Протокольдбург. Но можно просто Марсик 😽',
  'Мурр... А знаешь, что по паспорту я вообще-то Марсанваль фон Протокольдбург?',
  'Тсс... По документам я Марсанваль фон Протокольдбург. Но для тебя — просто Марсик.',
  'Знаешь, а моё любимое число — 8. Если положить его набок — получится бесконечность ∞. Красиво же?',
  'Мурр... Восьмёрка — моё любимое число. В ней прячется бесконечность, просто нужно её повернуть.',
];

/// Random "cat-speak" thank-you/compliment lines shown in a speech bubble
/// each time the user pets the cat in [CatPettingDialog]. Deliberately not
/// run through the l10n system - these are playful flavor text specific to
/// this fork, not core UI strings, and machine-translating purr sounds
/// wouldn't read naturally in other languages anyway.
const _genericCatCompliments = <String>[
  'Мурр~ Спасибо! Ты лучший!',
  'Мяу! Обожаю, когда меня гладят!',
  'Мурр-мурр... Ещё чуть-чуть?',
  'Спасибо! Ты так обо мне заботишься!',
  'Мяяяу~ Приятно!',
  'Мурлык-мурлык, ты добрый человек!',
  'Спасибо за ласку! Теперь я точно защищу твой трафик!',
  'Мурр! От тебя пахнет добротой!',
  'Мяу-мяу, продолжай, мне нравится!',
  'Спасибо! Я теперь замурчу от счастья!',
  'Мурр~ Лучший хозяин в этой сети (и не только)!',
  'Спасибо, теперь я готов туннелировать весь день!',
  'Мяу! Ты знаешь, как порадовать кота!',
  'Мурр-мурр-мурр! Ещё разок?',
  'Спасибо! Ты заслуживаешь VIP-туннель!',
  'Мурлык! У тебя золотые руки!',
  'Мяу, спасибо! Мур на максималках!',
  'Мурр... От такой ласки даже пакеты быстрее летят!',
  'Спасибо! Ты сделал мой день!',
  'Мяу-мяу-мур! Я весь твой!',
  'Мурр~ Ты знаешь толк в котиках!',
  'Спасибо! Обещаю шифровать всё как надо!',
  'Мяу! Ласковые руки — лучшая защита!',
  'Мурр-мурр, спасибо тебе большое!',
  'Спасибо! Теперь мурчу на всех частотах!',
  'Мяу~ Ты особенный человек!',
  'Мурр! Продолжай в том же духе!',
  'Спасибо за нежность! Это моя любимая часть дня!',
  'Мяу-мяу! Ты просто чудо!',
  'Мурлык-мурлык~ Обожаю такое внимание!',
  'Спасибо! Я теперь самый счастливый VPN-кот!',
  'Мурр... Ещё немного и я замурчу навсегда!',
  'Мяу! У тебя явно доброе сердце!',
  'Спасибо! Так держать!',
  'Мурр-мяу! Ты лучший из лучших!',
  'Спасибо тебе! Мур-мур-мур!',
  'Мяу~ Обожаю такие моменты!',
  'Мурр! Ты заслужил все мои мурчания!',
  'Спасибо! С тобой даже разрыв соединения не страшен!',
  'Мяу-мяу-мяу! Продолжай меня баловать!',
  'Мурлык! Ты знаешь путь к кошачьему сердцу!',
  'Спасибо большое! Это было приятно!',
  'Мурр~ Теперь я точно защищу тебя на все 100%!',
  'Мяу! Спасибо, что заглянул проведать меня!',
];

/// "{address}" resolves to a gender-correct noun ("хозяин"/"хозяйка"), or
/// drops out entirely if the owner skipped that question.
List<String> _personalizedTemplates(String? name, CatOwnerGender? gender) {
  final address = switch (gender) {
    CatOwnerGender.host => 'хозяин',
    CatOwnerGender.hostess => 'хозяйка',
    null => null,
  };
  final kind = switch (gender) {
    CatOwnerGender.host => 'добрый',
    CatOwnerGender.hostess => 'добрая',
    null => 'добрый человек',
  };

  return [
    if (name != null) 'Мурр, $name! Ты лучше всех!',
    if (name != null) 'Спасибо, $name! Обожаю, когда ты рядом!',
    if (address != null) 'Мяу, $address! Ты знаешь, как меня порадовать!',
    if (name != null && address != null) 'Спасибо, $address $name! Мур-мур-мур!',
    'Мурр~ Какой ты $kind!',
  ];
}

/// The full pool to pick a random compliment from - generic lines plus a
/// few personalized ones (only present once the owner shared a name and/or
/// gender in [CatIntroDialog]).
List<String> catComplimentsFor({String? name, CatOwnerGender? gender}) => [
  ..._genericCatCompliments,
  ..._personalizedTemplates(name, gender),
];

/// Guaranteed easter egg on round pet counts (see
/// [CatOwnerPreferences.petCount]) - replaces the compliment that moment.
/// Null for any other count.
String? catMilestoneLine(int count) {
  final isMilestone = const {50, 100, 250, 500}.contains(count) || (count >= 1000 && count % 1000 == 0);
  if (!isMilestone) {
    return null;
  }

  return switch (count) {
    50 => 'Ого, уже 50 поглаживаний! Кажется, мы подружились 😺',
    100 => 'Сто поглаживаний! Официально объявляю тебя своим человеком 😽',
    250 => '250! Я уже узнаю тебя по рукам. Мурр~',
    500 => 'Пятьсот поглаживаний... Марсанваль фон Протокольдбург тронут до глубины туннеля 🥹',
    1000 => 'ТЫСЯЧА! Ты гладишь меня больше, чем я шифрую пакетов. Почти.',
    _ => '$count поглаживаний! Это уже не ласка, это традиция 💙',
  };
}

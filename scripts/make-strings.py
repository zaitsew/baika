#!/usr/bin/env python3
"""Writes App/Localizable.xcstrings and App/InfoPlist.xcstrings from the table below.

The table is the single place the Russian interface copy lives. English is the source
language; a key with no entry here simply shows its English text.

    python3 scripts/make-strings.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "App"

# key (English, as written in the code) -> Russian
UI = {
    # Brand: the home-screen name is "Байка" on a Russian device
    "Baika": "Байка",
    # Tabs
    "Perform": "Рассказ",
    "Library": "Библиотека",
    "Talk": "Беседа",
    "Settings": "Настройки",
    # Perform form
    "Tell": "Рассказать",
    "A story for the ear, on any topic.": "История для слуха — на любую тему.",
    "Topic": "Тема",
    "What should the story be about?": "О чём рассказать?",
    "Type, or tap the microphone on the keyboard to dictate.": "Напишите или нажмите микрофон на клавиатуре, чтобы надиктовать.",
    "Style": "Стиль",
    "Your own style": "Свой стиль",
    "For example: a noir detective in the rain": "Например: нуар-детектив под дождём",
    "Length": "Длина",
    "%lld min": "%lld мин",
    "Language": "Язык",
    "Voice": "Голос",
    # Stage
    "Writing your story…": "Пишу историю…",
    "Something stopped": "Что-то остановилось",
    "Telling": "Рассказываю",
    "Preparing the voice…": "Готовлю голос…",
    "Paused": "Пауза",
    "The end": "Конец",
    "Narrated with the backup voice": "Озвучено запасным голосом",
    "Close": "Закрыть",
    "Try again": "Повторить",
    "Back": "Назад",
    "New story": "Новая история",
    # Consent
    "Before the first story": "Перед первой историей",
    "Your topic and the style you pick go to Anthropic, which writes the story.": "Тема и выбранный стиль уходят в Anthropic — он пишет историю.",
    "The written story goes to ElevenLabs, which reads it aloud. If ElevenLabs is unavailable, OpenAI reads it instead.": "Готовый текст уходит в ElevenLabs — он читает его вслух. Если ElevenLabs недоступен, читает OpenAI.",
    "Everything passes through Fabrique Accounts, the sign-in service behind Baika. Stories and audio stay on this iPhone.": "Всё идёт через Fabrique Accounts — сервис входа, на котором работает Байка. Истории и аудио хранятся на этом iPhone.",
    "Stories are written by AI and can contain mistakes.": "Истории пишет ИИ, в них бывают ошибки.",
    "Agree and tell": "Согласен, рассказывай",
    "Not now": "Не сейчас",
    # Player
    "Progress": "Прогресс",
    "%@ of %@": "%@ из %@",
    "Back 15 seconds": "Назад на 15 секунд",
    "Forward 15 seconds": "Вперёд на 15 секунд",
    "Pause": "Пауза",
    "Play": "Играть",
    # Library
    "No stories yet": "Историй пока нет",
    "Stories you ask for appear here, and play without a connection.": "Здесь появятся ваши истории. Они играют без интернета.",
    "Sign in on the Perform tab to ask for a story. Stories you make appear here, and play without a connection.": "Войдите на вкладке «Рассказ», чтобы заказать историю. Здесь появятся ваши истории. Они играют без интернета.",
    "Finish the narration": "Дочитать вслух",
    "Part of the audio is not on this device.": "Часть аудио нет на этом устройстве.",
    "Sign in to narrate the rest of this story.": "Войдите, чтобы озвучить остаток истории.",
    "Tell a story from the Perform tab once to agree to the AI terms.": "Закажите одну историю на вкладке «Рассказ», чтобы принять условия ИИ.",
    "Delete this story and its audio?": "Удалить историю и её аудио?",
    "Delete": "Удалить",
    "Share": "Поделиться",
    "Share text": "Поделиться текстом",
    "Share audio": "Поделиться аудио",
    "The audio could not be prepared for sharing.": "Не удалось подготовить аудио.",
    # Talk
    "Talk is coming": "Беседа скоро появится",
    "Soon you will be able to speak with the storyteller out loud, and steer the story as it goes.": "Скоро вы сможете говорить с рассказчиком вслух и направлять историю на ходу.",
    # Sign-in
    "Pick a topic and a style. Hear it told as a story.": "Выберите тему и стиль. Послушайте, как это расскажут.",
    "or": "или",
    "Sign in": "Войти",
    "Create account": "Создать аккаунт",
    "Email me a sign-in link": "Прислать ссылку для входа",
    "Email": "Почта",
    "Choose a password (6+ characters)": "Придумайте пароль (от 6 символов)",
    "Password": "Пароль",
    "Open my library": "Открыть библиотеку",
    "Check %@ to confirm the address.": "Проверьте %@, чтобы подтвердить адрес.",
    "Check %@ for the link.": "Ссылка отправлена на %@.",
    "Apple did not return an identity token.": "Apple не вернул токен входа.",
    # Settings
    "Account": "Аккаунт",
    "You are not signed in. Sign in on the Perform tab to ask for stories. Your library works without an account.": "Вы не вошли. Войдите на вкладке «Рассказ», чтобы заказывать истории. Библиотека работает без аккаунта.",
    "Send topics to AI providers": "Отправлять темы ИИ-провайдерам",
    "AI": "ИИ",
    "Anthropic writes the story. ElevenLabs reads it aloud, and OpenAI reads it if ElevenLabs is unavailable. Turn this off and Baika asks again before the next story.": "Историю пишет Anthropic. Вслух читает ElevenLabs, а если он недоступен — OpenAI. Выключите, и Байка спросит снова перед следующей историей.",
    "About": "О приложении",
    "Version": "Версия",
    "Baika is an AI storyteller. Stories are written by AI and can contain mistakes.": "Байка — рассказчик на основе ИИ. Истории пишет ИИ, в них бывают ошибки.",
    # Failures (FailureText)
    "The story came back empty. Try again.": "История пришла пустой. Попробуйте ещё раз.",
    "Something went wrong. Try again.": "Что-то пошло не так. Попробуйте ещё раз.",
    "Your session has ended. Sign in again.": "Сессия закончилась. Войдите снова.",
    "This month's AI allowance is used up.": "Лимит ИИ на этот месяц исчерпан.",
    "Too many requests. Try again in a minute.": "Слишком много запросов. Попробуйте через минуту.",
    "The narration limit is reached for now. Try again later.": "Лимит озвучки пока исчерпан. Попробуйте позже.",
    "That topic is too long. Shorten it.": "Тема слишком длинная. Сократите её.",
    "The service refused the request. Try again.": "Сервис отклонил запрос. Попробуйте ещё раз.",
    "The service is unavailable right now. Try again in a moment.": "Сервис сейчас недоступен. Попробуйте через минуту.",
    "No connection. Check the network and try again.": "Нет соединения. Проверьте сеть и повторите.",
    "The voice returned no audio. Try again.": "Голос не вернул звук. Попробуйте ещё раз.",
    # App Intents (Siri, Shortcuts, Spotlight)
    "Tell a story": "Рассказать историю",
    "Write a story on a topic in a style, narrate it aloud and open the player.": "Написать историю на тему в выбранном стиле, озвучить и открыть плеер.",
    "Stories": "Истории",
    "What the story is about.": "О чём история.",
    "A writer or a manner, for example Dovlatov or a noir detective. Empty keeps your last choice.": "Писатель или манера, например Довлатов или нуар-детектив. Пусто — останется прошлый выбор.",
    "Telling a story about %@.": "Рассказываю историю: %@.",
    "Replay my last story": "Повторить последнюю историю",
    "Play your newest story again from the start. It plays offline.": "Включить новейшую историю с начала. Она играет без интернета.",
    "You have no stories yet. Ask for one first.": "Историй пока нет. Сначала закажите одну.",
    "Playing %@.": "Играет: %@.",
    "Part of the audio for %@ is not downloaded yet. I opened it.": "Часть аудио для «%@» ещё не загружена. История открыта.",
    "%@ is still being narrated. I opened it.": "«%@» ещё озвучивается. История открыта.",
    "Continue the story": "Продолжить историю",
    "Play on a story you paused, or write and narrate the next part of your latest story.": "Продолжить историю с паузы или написать и озвучить следующую часть последней истории.",
    "Continuing %@.": "Продолжаем: %@.",
    "Writing the next part of %@.": "Пишу продолжение: %@.",
}

SHORTCUT_PHRASES = {
    "Tell me a story with ${applicationName}": "Расскажи мне историю в ${applicationName}",
    "Tell a story in ${applicationName}": "Расскажи историю в ${applicationName}",
    "Ask ${applicationName} for a story": "Попроси ${applicationName} рассказать историю",
    "Replay my last story in ${applicationName}": "Повтори мою последнюю историю в ${applicationName}",
    "Play my last ${applicationName} story again": "Включи ещё раз мою последнюю историю в ${applicationName}",
    "Continue the story in ${applicationName}": "Продолжи историю в ${applicationName}",
    "Continue my story with ${applicationName}": "Продолжи мою историю в ${applicationName}",
}

INFO = {
    "CFBundleDisplayName": ("Baika", "Байка"),
    "NSMicrophoneUsageDescription": (
        "Baika uses the microphone when you dictate the topic of a story.",
        "Байка использует микрофон, когда вы диктуете тему истории.",
    ),
    "NSSpeechRecognitionUsageDescription": (
        "Baika turns your spoken topic into text so it can write the story.",
        "Байка превращает вашу речь в текст, чтобы написать историю.",
    ),
}


def catalog(entries):
    strings = {}
    for key, (en, ru) in entries.items():
        strings[key] = {
            "localizations": {
                "en": {"stringUnit": {"state": "translated", "value": en}},
                "ru": {"stringUnit": {"state": "translated", "value": ru}},
            }
        }
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def write(name, entries):
    path = ROOT / name
    path.write_text(json.dumps(catalog(entries), ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    print(f"wrote {path.relative_to(ROOT.parent)} ({len(entries)} keys)")


write("Localizable.xcstrings", {key: (key, ru) for key, ru in UI.items()})
write("InfoPlist.xcstrings", INFO)
write("AppShortcuts.xcstrings", {key: (key, ru) for key, ru in SHORTCUT_PHRASES.items()})

#!/usr/bin/env python3
"""Android manifest yaması (idempotent).

- INTERNET iznini ekler.
- https VIEW intent'ini <queries> altına ekler (Android 11+ paket görünürlüğü).
  Şablonda zaten bir <queries> bloğu varsa (PROCESS_TEXT) İKİNCİ blok
  oluşturulmaz; intent var olan bloğun içine eklenir.
- Uygulama etiketini "Gitpush" yapar.
- Güvenlik: android:allowBackup="false" (token/kişisel veriler bulut yedeğine
  ve adb backup'a girmesin) ve android:usesCleartextTraffic="false" (düz HTTP
  trafiği kapalı) ayarlarını <application> etiketine ekler/zorlar.

Kullanım: patch_android_manifest.py <AndroidManifest.xml> [--verify]
"""
import re
import sys

INTERNET = '<uses-permission android:name="android.permission.INTERNET"/>'
HTTPS_INTENT = (
    '<intent>\n'
    '            <action android:name="android.intent.action.VIEW" />\n'
    '            <category android:name="android.intent.category.BROWSABLE" />\n'
    '            <data android:scheme="https" />\n'
    '        </intent>'
)
HTTPS_RE = re.compile(
    r'<intent>(?:(?!</intent>).)*android\.intent\.action\.VIEW(?:(?!</intent>).)*'
    r'android:scheme="https"(?:(?!</intent>).)*</intent>',
    re.S,
)


def patch(text: str) -> str:
    if 'android.permission.INTERNET' not in text:
        text = re.sub(r'(<manifest\b[^>]*>)', lambda m: m.group(1) + '\n    ' + INTERNET, text, count=1)

    if not HTTPS_RE.search(text):
        if re.search(r'<queries\s*>', text):
            text = re.sub(r'(<queries\s*>)', lambda m: m.group(1) + '\n        ' + HTTPS_INTENT, text, count=1)
        elif re.search(r'<queries\s*/>', text):
            text = re.sub(r'<queries\s*/>', '<queries>\n        ' + HTTPS_INTENT + '\n    </queries>', text, count=1)
        else:
            text = re.sub(r'(<application\b)', '<queries>\n        ' + HTTPS_INTENT + '\n    </queries>\n    \\1', text, count=1)

    text = re.sub(r'android:label="[^"]*"', 'android:label="Gitpush"', text)
    text = set_application_attr(text, 'allowBackup', 'false')
    text = set_application_attr(text, 'usesCleartextTraffic', 'false')
    return text


def set_application_attr(text: str, name: str, value: str) -> str:
    """<application ...> etiketinde android:<name> değerini zorlar (yoksa ekler)."""
    m = re.search(r'<application\b[^>]*>', text, re.S)
    if not m:
        return text
    tag = m.group(0)
    attr_re = re.compile(r'android:' + name + r'="[^"]*"')
    if attr_re.search(tag):
        new_tag = attr_re.sub('android:%s="%s"' % (name, value), tag)
    else:
        new_tag = tag.replace('<application', '<application android:%s="%s"' % (name, value), 1)
    return text[:m.start()] + new_tag + text[m.end():]


def verify(text: str) -> list:
    errors = []
    if 'android.permission.INTERNET' not in text:
        errors.append('INTERNET izni manifestte yok')
    if len(re.findall(r'<queries\b', text)) != 1:
        errors.append('<queries> bloğu tam olarak 1 adet olmalı')
    if 'android.intent.action.VIEW' not in text:
        errors.append('android.intent.action.VIEW satırı manifestte yok')
    if not HTTPS_RE.search(text):
        errors.append('https VIEW intent\'i <queries> içinde yok')
    app = re.search(r'<application\b[^>]*>', text, re.S)
    if app:
        if 'android:allowBackup="false"' not in app.group(0):
            errors.append('android:allowBackup="false" ayarlı değil')
        if 'android:usesCleartextTraffic="false"' not in app.group(0):
            errors.append('android:usesCleartextTraffic="false" ayarlı değil')
    return errors


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    with open(path, encoding='utf-8') as f:
        text = f.read()

    if '--verify' not in sys.argv:
        text = patch(text)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)

    errors = verify(text)
    for e in errors:
        print('::error::' + e)
    if errors:
        return 1
    print('Manifest doğrulandı: INTERNET + https VIEW <queries> + yedekleme/cleartext kapalı.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

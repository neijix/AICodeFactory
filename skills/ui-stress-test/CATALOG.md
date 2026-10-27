# Worst-case catalog

Values to feed a UI on purpose. All of them are invented or generic; none belongs to a real
person or account. Domains use `example.com` / `example.org` (reserved for documentation).

Invisible characters (joiners, variation selectors, combining marks, zero-width spaces) are
written as JavaScript escapes such as `"\u200D"`, never pasted raw: a raw one is invisible in
review and survives copy-paste in surprising ways. Paste the escaped string into JS source, or
decode it there; do not retype it.

A note on the headless check's `--forbid-text "undefined"`: if you use the literal strings
`"null"` or `"undefined"` as values (a surname "Null" exists), drop that flag for the run or use
a different marker.

## Long names

| Case | Value |
|---|---|
| very long single word | `Pneumonoultramicroscopicsilicovolcanoconiosis` |
| long single word, Finnish | `Lentokonesuihkuturbiinimoottoriapumekaanikkoaliupseerioppilas` |
| long multi-word name | `Maximiliana Konstantinopoulou-Vanderbergh de la Fuente-Østergaard` |
| many short parts | `Ana María José Luisa de los Ángeles Pérez y Pérez` |
| long title with no spaces at the break point | `Quarterly-planning-review-for-the-infrastructure-modernisation-programme` |
| long product name, Japanese | `国際化対応テスト用の非常に長い製品名サンプルデラックス版` |

## Unbreakable strings

| Case | Value |
|---|---|
| long email | `maximiliana.konstantinopoulou-vanderbergh@engineering.subsidiary.example.com` |
| email with plus tag | `first.last+newsletter-2026-october-campaign@example.org` |
| long URL | `https://example.com/projects/2026/quarterly-reports/drafts/final-final-v7/attachments/summary.pdf?download=true&ref=sidebar-navigation` |
| hash | `sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08` |
| git commit | `4b825dc642cb6eb9a060e54bf8d69288fbee4904` |
| UUID | `123e4567-e89b-12d3-a456-426614174000` |
| Windows path | `%LOCALAPPDATA%\Programs\Example Application\resources\app\node_modules\.cache\index.json` |
| POSIX path | `~/projects/example-monorepo/packages/frontend/src/components/settings/advanced/NotificationPreferences.test.tsx` |
| API key look-alike (clearly fake) | `demo_key_0000000000000000000000000000000000000000` |
| repeated character | `"W".repeat(80)` (the widest Latin letter) |

## One character, empty and blank

| Case | Value |
|---|---|
| one character | `"A"` |
| one narrow character | `"i"` |
| one CJK character | `"李"` |
| empty string | `""` |
| whitespace only | `"   "` |
| dash or zero that looks like a placeholder | `"-"`, `"0"` |
| a name that is a keyword | `"Null"`, `"True"`, `"None"` |
| text that looks like markup (must appear as text) | `"<b>not bold</b>"`, `"Tom & Jerry <tom@example.com>"` |
| leading and trailing spaces | `"  padded value  "` |
| a line break inside a one-line field | `"first line\nsecond line"` |

## Missing and wrong-typed fields

```js
{ name: 'Only a name' }                                  // every other key absent
{ name: null, email: null, avatar: null }                // explicit nulls
{ name: 'No tags', tags: [] }                            // empty array
{ name: 'No address', address: {} }                      // empty object where fields are read
{ name: 'Nested gap', address: { city: undefined } }     // reading address.city.name throws
{ name: 'Stringly', count: '42', active: 'false' }       // numbers and booleans as strings
{ name: 'Partial date', createdAt: '' }                  // empty date
```

## Counts and quantities

| Case | Value |
|---|---|
| zero | `0` |
| one (singular) | `1` |
| two (plural; also the "dual" form in some languages) | `2` |
| edge of two digits | `99`, `100` |
| edge of three digits | `999`, `1000` |
| a million and more | `1000000`, `1284917`, `1234567890` |
| largest safe integer | `9007199254740991` |
| negative | `-1`, `-15000` |
| fractional where integers are assumed | `2.5` |
| not a number | `NaN`, `Infinity` |

## Many items, zero items

- zero items (the empty state), one item, two items (singular and plural layouts)
- exactly one more than fits on screen, so the scroll or "show more" kicks in
- 100 items (pagination or scrolling), 10 000 items (rendering speed; consider virtualising)
- one item with very long content among short ones (does the row height break the grid?)
- one item with 30 tags, chips or avatars (does the row wrap or clip?)
- deep nesting: a tree or thread six levels deep at 320 px

## Long labels on buttons, tabs and menus

| Case | Value |
|---|---|
| long English action | `Download all attachments as a ZIP archive` |
| same in German | `Alle Anhänge als ZIP-Archiv herunterladen` |
| long tab label | `Benachrichtigungseinstellungen` |
| two-word button that becomes three lines | `Änderungen übernehmen und schließen` |
| many tabs | 12 tabs: Overview, Activity, Members, Permissions, Integrations, Webhooks, Billing, Usage, Audit log, Security, Advanced, Danger zone |
| menu item with a shortcut | `Duplicate selection to another workspace   Ctrl+Shift+D` |

## Translations that grow

German and Finnish text often runs 30 to 40 % longer than English, short strings even more
(a 4-letter English label can double).

| English | German | Finnish |
|---|---|---|
| Save | Speichern | Tallenna |
| Settings | Einstellungen | Asetukset |
| Sign out | Abmelden | Kirjaudu ulos |
| Search results | Suchergebnisse | Hakutulokset |
| Account management | Benutzerkontoverwaltung | Käyttäjätilien hallinta |
| Mark all as read | Alle als gelesen markieren | Merkitse kaikki luetuiksi |
| Data protection compliance check | Datenschutzgrundverordnungskonformitätsprüfung | Tietosuoja-asetuksen vaatimustenmukaisuuden tarkistus |

French and Spanish add 15 to 25 %; CJK usually gets shorter in characters but taller glyphs.

## Non-Latin scripts

| Script | Value | What it tests |
|---|---|---|
| Chinese, no spaces | `这是一个没有任何空格的很长的中文标题用于测试自动换行` | line breaking without spaces |
| Japanese, mixed | `プロジェクト「新規開発」の進捗レポート（第3四半期）` | full-width punctuation |
| Korean | `대한민국 서울특별시 강남구 테헤란로 123` | Hangul spacing |
| Arabic, RTL | `محمد بن عبد الله الهاشمي` | right-to-left layout, `dir="auto"` |
| Arabic with digits and parentheses | `طلب رقم 12345 (قيد المعالجة)` | bidi reordering of numbers and brackets |
| Hebrew, RTL | `שלום עולם, זוהי כותרת ארוכה למדי` | RTL with a comma |
| mixed LTR in RTL | `הקובץ report-final.pdf נשמר` | a Latin word inside RTL |
| Devanagari | `नमस्ते दुनिया, यह एक परीक्षण शीर्षक है` | stacked conjuncts, taller line height |
| Thai, no spaces | `ภาษาไทยไม่มีช่องว่างระหว่างคำจึงตัดบรรทัดยาก` | word breaking needs a dictionary |
| Cyrillic, long | `Достопримечательности Санкт-Петербурга` | long words in another alphabet |
| Greek | `Καλημέρα κόσμε` | accents and case mapping |

## Emoji

Write these exactly as the escapes below in JS source.

| Case | JS string |
|---|---|
| single emoji | `"\u{1F600}"` |
| with skin tone | `"\u{1F44D}\u{1F3FD}"` |
| flag (two regional indicators) | `"\u{1F1EB}\u{1F1F7}"` |
| family (joined sequence) | `"\u{1F468}\u200D\u{1F469}\u200D\u{1F467}"` |
| family of four | `"\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}"` |
| profession with tone (joined) | `"\u{1F469}\u{1F3FE}\u200D\u{1F4BB}"` |
| keycap | `"1\uFE0F\u20E3"` |
| red heart with presentation selector | `"\u2764\uFE0F"` |
| a name that is only emoji | `"\u{1F525}\u{1F525}\u{1F525}"` |
| emoji between words | `"Launch \u{1F680} party \u{1F389} on Friday"` |

The joined family is one character to the reader but eight UTF-16 code units: `.length`,
`.slice()` and `substring()` cut it into pieces. Count and truncate with `Intl.Segmenter`.

## Combining marks and invisible characters

| Case | JS string |
|---|---|
| precomposed vs combining (look identical, compare unequal) | `"\u00E9"` vs `"e\u0301"` |
| stacked combining marks | `"Z\u0351\u0359a\u0352\u035Cl\u0350\u0353g\u0357\u034Do"` |
| Vietnamese, two marks per letter | `"Nguy\u1EC5n Th\u1ECB Ho\u00E0ng"` |
| zero-width space inside a word | `"break\u200Bpoint"` |
| soft hyphen | `"Donau\u00ADdampf\u00ADschiff\u00ADfahrt"` |
| non-breaking spaces that refuse to wrap | `"keep\u00A0these\u00A0words\u00A0together\u00A0on\u00A0one\u00A0line"` |

## Dates, times and time zones

| Case | Value |
|---|---|
| Unix epoch (what a `0` or `null` timestamp becomes) | `1970-01-01T00:00:00Z` |
| far past | `1900-01-01T00:00:00Z` |
| 32-bit overflow | `2038-01-19T03:14:08Z` |
| far future | `9999-12-31T23:59:59Z` |
| leap day | `2028-02-29T12:00:00Z` |
| local time that does not exist (spring forward, Paris) | `2026-03-29T02:30` in `Europe/Paris` |
| local time that happens twice (fall back, Paris) | `2026-10-25T02:30` in `Europe/Paris` |
| furthest ahead zone | `Pacific/Kiritimati` (UTC+14) |
| furthest behind zone | `Pacific/Pago_Pago` (UTC-11) |
| quarter-hour offset | `Asia/Kathmandu` (UTC+5:45) |
| half-hour daylight shift | `Australia/Lord_Howe` |
| in the future (relative labels) | now + 3 days ("in 3 days", not "-3 days ago") |
| just now and long ago | now - 2 s, now - 11 years |
| durations | `0 s`, `59 s`, `25 h`, `400 days` |
| longest month and weekday names | `September`, German `Donnerstag, 30. September 2026` |

## Numbers and currency

| Case | Value |
|---|---|
| floating-point surprise | `0.1 + 0.2` (shows `0.30000000000000004` if unformatted) |
| negative zero | `-0` |
| tiny percentage | `0.0004 %` (rounds to `0 %`: is that honest?) |
| over 100 % | `1250 %` |
| huge amount | `1234567890.12` EUR |
| no minor unit | `1500` JPY (`¥1,500`, no decimals) |
| three decimals | `12.345` BHD |
| Indian grouping | `1234567` INR (`₹12,34,567`) |
| Swiss grouping | `1234.5` CHF in `de-CH` (`CHF 1’234.50`) |
| comma decimal | `1234.5` EUR in `de-DE` (`1.234,50 €`) |
| negative money | `-42.5` USD (minus sign, or parentheses in accounting style) |
| scientific | `6.02e23`, `1e-9` |

## Images

Make them locally; never hotlink a placeholder service.

```js
// Any size, any colour, no network: an inline SVG data URL.
const fakeImage = (w, h, fill = '#8a8') =>
  'data:image/svg+xml,' + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}">` +
    `<rect width="100%" height="100%" fill="${fill}"/></svg>`);
```

| Case | Value |
|---|---|
| 1 x 1 pixel | `fakeImage(1, 1)` |
| panorama | `fakeImage(8000, 200)` |
| very tall | `fakeImage(200, 8000)` |
| very large square | `fakeImage(6000, 6000)` |
| transparent | `fakeImage(400, 400, 'transparent')` |
| missing | `null` or `""` (the fallback avatar or initials) |
| broken | a same-origin path that 404s, such as `/dev/missing.png` |

## Slow and failed loads

Simulate in the data layer of the dev toggle, not by depending on a remote server:

| Case | How |
|---|---|
| slow | `await new Promise((r) => setTimeout(r, 4000))` before returning data |
| never finishes | return a promise that never resolves (the loading state stays) |
| fails | throw an `Error`; also a response with status 500 and an HTML body |
| unauthorised | status 401 (does the UI send the user to sign in?) |
| partial | one of three parallel requests fails; the other two render |
| empty success | status 200 with `[]` or `{}` |
| out of order | a slow first request resolves after a fast second one (stale data wins?) |
| offline | `navigator.onLine === false` and every fetch rejects |

## A ready-made set

A starting point for `worstCaseItems()`; adapt keys to the component's data.

```js
function worstCaseItems() {
  return [
    { id: 1, name: 'Jamie Ortega', email: 'jamie@example.com', unread: 3 },  // the baseline
    { id: 2, name: 'Maximiliana Konstantinopoulou-Vanderbergh de la Fuente-Østergaard',
      email: 'maximiliana.konstantinopoulou-vanderbergh@engineering.subsidiary.example.com',
      unread: 1284917 },
    { id: 3, name: 'Pneumonoultramicroscopicsilicovolcanoconiosis', email: '', unread: 0 },
    { id: 4, name: 'A', email: null, unread: 1 },
    { id: 5, name: 'محمد بن عبد الله الهاشمي', email: 'm.hashimi@example.org', unread: -1 },
    { id: 6, name: '\u{1F468}\u200D\u{1F469}\u200D\u{1F467} Family \u{1F44D}\u{1F3FD}',
      email: 'first.last+newsletter-2026-october-campaign@example.org', unread: 999 },
    { id: 7, name: '这是一个没有任何空格的很长的中文标题用于测试自动换行', unread: 100 },
    { id: 8, name: '<b>not bold</b>' },                                    // keys missing
  ];
}
```

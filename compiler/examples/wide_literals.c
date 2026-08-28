/*
 * The word-addressed target defines wchar_t as signed int, char16_t as
 * unsigned short, and char32_t as unsigned int.  Every code unit occupies one
 * addressed 32-bit word.  The u8 form uses UTF-8 byte values in those words;
 * the other execution-wide encodings map one Unicode scalar to one word.
 */

typedef int wchar_t;
typedef unsigned short char16_t;
typedef unsigned int char32_t;

wchar_t wide_text[] = L"A\u03a9\U0001f600";
char16_t utf16_text[] = u"B\u03a9\U0001f600";
char32_t utf32_text[] = U"C\u03a9\U0001f600";
char utf8_text[] = u8"D\u03a9\U0001f600";
wchar_t promoted_text[] = "x" L"\u03a9" "y";
char promoted_utf8[] = "\u03a9" u8"";
char32_t escaped_text[] = U"\x1234";
char32_t raw_text[] = U"Ω😀";
char raw_utf8[] = u8"Ω";

wchar_t *wide_pointer = L"z";
char16_t *utf16_pointer = u"q";
char32_t *utf32_pointer = U"r";
char *utf8_pointer = u8"s";

int remote_literal_types(wchar_t wide, char16_t utf16, char32_t utf32) {
  return wide + utf16 + utf32 + computer();
}

int main(void) {
  int score = 0;

  if (sizeof(wide_text) == 4 && wide_text[0] == 65 &&
      wide_text[1] == 0x3a9 && wide_text[2] == 0x1f600 &&
      wide_text[3] == 0)
    score += 1;

  if (sizeof(utf16_text) == 4 && utf16_text[0] == 66U &&
      utf16_text[1] == 0x3a9U && utf16_text[2] == 0x1f600U &&
      utf16_text[3] == 0U)
    score += 2;

  if (sizeof(utf32_text) == 4 && utf32_text[0] == 67U &&
      utf32_text[1] == 0x3a9U && utf32_text[2] == 0x1f600U &&
      utf32_text[3] == 0U)
    score += 4;

  if (sizeof(utf8_text) == 8 && utf8_text[0] == 68 &&
      utf8_text[1] == 0xce && utf8_text[2] == 0xa9 &&
      utf8_text[3] == 0xf0 && utf8_text[4] == 0x9f &&
      utf8_text[5] == 0x98 && utf8_text[6] == 0x80 &&
      utf8_text[7] == 0)
    score += 8;

  if (sizeof(promoted_text) == 4 && promoted_text[0] == 120 &&
      promoted_text[1] == 0x3a9 && promoted_text[2] == 121 &&
      promoted_text[3] == 0)
    score += 16;

  if (sizeof(promoted_utf8) == 3 && promoted_utf8[0] == 0xce &&
      promoted_utf8[1] == 0xa9 && promoted_utf8[2] == 0)
    score += 32;

  if (_Generic(L'A', int: 1, default: 0) &&
      _Generic(u'B', unsigned short: 1, default: 0) &&
      _Generic(U'C', unsigned int: 1, default: 0) &&
      L'\u03a9' == 0x3a9 && u'\U0001f600' == 0x1f600U &&
      U'\U0001f600' == 0x1f600U)
    score += 64;

  if (sizeof(escaped_text) == 2 && escaped_text[0] == 0x1234U &&
      escaped_text[1] == 0U && sizeof(raw_text) == 3 &&
      raw_text[0] == 0x3a9U && raw_text[1] == 0x1f600U &&
      raw_text[2] == 0U && sizeof(raw_utf8) == 3 &&
      raw_utf8[0] == 0xce && raw_utf8[1] == 0xa9 && raw_utf8[2] == 0)
    score += 128;

  if ('AB' == 0x4142 && L'CD' == 0x4344)
    score += 256;

  if (*wide_pointer == 122 && *utf16_pointer == 113U &&
      *utf32_pointer == 114U && *utf8_pointer == 115)
    score += 512;

  return score + remote_literal_types(L'A', u'B', U'C')@1;
}

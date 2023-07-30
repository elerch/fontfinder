#include <stdlib.h>
#include <fontconfig/fontconfig.h>

/* #<{(| FcChar32 FcCharSetCount (const FcCharSet *a); |)}># */
/* void printCharacters(FcPattern* fontPattern) { */
/*     FcCharSet* charset; */
/*     if (FcPatternGetCharSet(fontPattern, FC_CHARSET, 0, &charset) == FcResultMatch) { */
/*         FcChar32 ucs4; */
/*         FcCharSetIter iter; */
/*         FcCharSetIterInit(charset, &iter); */
/*         printf("Supported characters:\n"); */
/*         while (FcCharSetIterNext(&iter, &ucs4)) { */
/*             printf("%lc ", (wint_t)ucs4); */
/*         } */
/*         printf("\n"); */
/*         FcCharSetDestroy(charset); */
/*     } */
/* } */

const FcChar32 MAX_UNICODE = 0x10FFFD;

void freeAllCharacters(unsigned int *chars) {
  free(chars);
}

int allCharacters(void* fontPattern, FcChar32 ** chars) {
  FcPattern* pat = (FcPattern*) fontPattern;
  FcCharSet* charset;
  if (FcPatternGetCharSet(pat, FC_CHARSET, 0, &charset) != FcResultMatch) {
    return -1;
  }
  FcChar32 count = FcCharSetCount(charset);
  unsigned int* char_array = (unsigned int*)malloc(count * sizeof(unsigned int));
  *chars = char_array;

  FcChar32 ucs4 = 0;
  size_t found = 0;
  size_t inx = 0;

  while (found < count && inx < MAX_UNICODE) {
    if (FcCharSetHasChar(charset, inx) == FcTrue) {
      char_array[ucs4] = inx;
      ucs4++;
      found++;
    }
    inx++;
  }
  FcCharSetDestroy(charset);
  if (found < count) {
    freeAllCharacters(*chars);
    return -2;
  }
  return ucs4;
}

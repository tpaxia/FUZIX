#include <kernel.h>
#include <kdata.h>
#include <printf.h>

extern void outchar(uint_fast8_t c);

void *memcpy(void *d, const void *s, size_t sz)
{
  unsigned char *dp = d;
  const unsigned char *sp = s;
  while(sz--)
    *dp++=*sp++;
  return d;
}

void *memset(void *d, int c, size_t sz)
{
  unsigned char *p = d;
  while(sz--)
    *p++ = c;
  return d;
}

size_t strlen(const char *p)
{
  const char *e = p;
  while(*e++);
  return e-p-1;
}

/* kputchar is used by kprintf - outputs via outchar */
void kputchar(uint_fast8_t c)
{
	if (c == '\n')
		outchar('\r');
	outchar(c);
}

/* CPU type detection - nothing to detect on Z8001 */
void set_cpu_type(void)
{
}


/* Binary relocation - TODO: implement for Z8000 a.out */
unsigned plt_relocate(struct exec *bf)
{
	return 0;
}

int memcmp(const void *a, const void *b, size_t n)
{
  const uint8_t *ap = a;
  const uint8_t *bp = b;
  while(n--) {
    if (*ap < *bp)
      return -1;
    if (*ap != *bp)
      return 1;
    ap++;
    bp++;
  }
  return 0;
}

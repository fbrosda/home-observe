#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gcrypt.h>

int main() {
  /* if (!gcry_check_version(GCRYPT_VERSION)) { */
  /*   fprintf(stderr, "libgcrypt version mismatch\n"); */
  /*   return 1; */
  /* } */
  /* gcry_control(GCRYCTL_DISABLE_SECMEM, 0); */
  /* gcry_control(GCRYCTL_INITIALIZATION_FINISHED, 0); */

  // Key and IV (nonce)
  unsigned char key[32] = {0}; // 256-bit key
  unsigned char iv[16]  = {0}; // 96-bit IV, recommended for GCM
  unsigned char tag[16];       // Authentication tag

  // Example plaintext
  const char *plaintext = "Hello AES-256-GCM!";
  size_t pt_len = strlen(plaintext);
  printf("strlen %d\n", pt_len);
  unsigned char ciphertext[pt_len];

  // Allocate cipher handle
  gcry_cipher_hd_t hd;
  gcry_error_t err = gcry_cipher_open(&hd, GCRY_CIPHER_AES256, GCRY_CIPHER_MODE_GCM, 0);
  if (err) {
    fprintf(stderr, "gcry_cipher_open failed: %s\n", gcry_strerror(err));
    return 1;
  }

  gcry_cipher_setkey(hd, key, sizeof(key));
  gcry_cipher_setiv(hd, iv, sizeof(iv));

  // Encrypt
  err = gcry_cipher_encrypt(hd, ciphertext, pt_len, plaintext, pt_len);
  if (err) {
    fprintf(stderr, "Encryption failed: %s\n", gcry_strerror(err));
    return 1;
  }

  // Get authentication tag
  gcry_cipher_gettag(hd, tag, sizeof(tag));

  // Decrypt (in a real scenario, use a new cipher handle or reset)
  /* gcry_cipher_reset(hd); */
  /* gcry_cipher_setkey(hd, key, sizeof(key)); */
  /* gcry_cipher_setiv(hd, iv, sizeof(iv)); */
  /* gcry_cipher_authenticate(hd, NULL, 0); // No additional authenticated data (AAD) */
  /* err = gcry_cipher_decrypt(hd, (unsigned char*)plaintext, pt_len, ciphertext, pt_len); */
  /* if (err) { */
  /*     fprintf(stderr, "Decryption failed: %s\n", gcry_strerror(err)); */
  /*     return 1; */
  /* } */

  /* // Verify tag */
  /* if (gcry_cipher_checktag(hd, tag, sizeof(tag))) { */
  /*     fprintf(stderr, "Tag verification failed!\n"); */
  /*     return 1; */
  /* } */

  printf("Plain text: %s\n", plaintext);

  printf("Ciphertext (hex): ");
  for (size_t i = 0; i < pt_len; i++) {
    printf("%02x", ciphertext[i]);
  }
  printf("\n");

  gcry_cipher_close(hd);
  return 0;
}

/**************************************************************************/
/*  test_crypto_mbedtls.cpp                                               */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "test_crypto_mbedtls.h"

#include "../crypto_mbedtls.h"

#include "tests/test_macros.h"

namespace TestCryptoMbedTLS {

void hmac_digest_test(HashingContext::HashType ht, String expected_hex) {
	CryptoMbedTLS crypto;
	PackedByteArray key = String("supersecretkey").to_utf8_buffer();
	PackedByteArray msg = String("Return of the MAC!").to_utf8_buffer();
	PackedByteArray digest = crypto.hmac_digest(ht, key, msg);
	String hex = String::hex_encode_buffer(digest.ptr(), digest.size());
	CHECK(hex == expected_hex);
}

void hmac_context_digest_test(HashingContext::HashType ht, String expected_hex) {
	HMACContextMbedTLS ctx;
	PackedByteArray key = String("supersecretkey").to_utf8_buffer();
	PackedByteArray msg1 = String("Return of ").to_utf8_buffer();
	PackedByteArray msg2 = String("the MAC!").to_utf8_buffer();
	Error err = ctx.start(ht, key);
	CHECK(err == OK);
	err = ctx.update(msg1);
	CHECK(err == OK);
	err = ctx.update(msg2);
	CHECK(err == OK);
	PackedByteArray digest = ctx.finish();
	String hex = String::hex_encode_buffer(digest.ptr(), digest.size());
	CHECK(hex == expected_hex);
}
} // namespace TestCryptoMbedTLS

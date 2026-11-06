CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wextra -Werror -O2

.PHONY: test clean integration-probe core-ios network-ios app ipa ipa-signed deb

test: build/test_theme_settings build/test_news_body build/test_qms build/test_compose build/test_news_article build/test_tls_split build/test_news_image build/test_http build/test_guest build/test_frame build/test_document build/test_text build/test_forum build/test_bbcode build/test_session build/test_tls_client build/test_resolve build/test_webp
	./build/test_theme_settings
	./build/test_news_body
	./build/test_qms
	./build/test_compose
	./build/test_news_image
	./build/test_news_article
	./build/test_tls_split
	./build/test_http
	./build/test_guest
	./build/test_frame
	./build/test_document
	./build/test_text
	./build/test_forum
	./build/test_bbcode
	./build/test_session
	python3 tests/test_tls.py
	./build/test_resolve
	./build/test_webp

WEBP_SRC := $(addprefix vendor/libwebp/src/, dec/alpha_dec.c dec/buffer_dec.c dec/frame_dec.c dec/idec_dec.c dec/io_dec.c dec/quant_dec.c dec/tree_dec.c dec/vp8_dec.c dec/vp8l_dec.c dec/webp_dec.c dsp/alpha_processing.c dsp/cpu.c dsp/dec.c dsp/dec_clip_tables.c dsp/filters.c dsp/lossless.c dsp/rescaler.c dsp/upsampling.c dsp/yuv.c utils/bit_reader_utils.c utils/color_cache_utils.c utils/filters_utils.c utils/huffman_utils.c utils/palette.c utils/quant_levels_dec_utils.c utils/rescaler_utils.c utils/random_utils.c utils/thread_utils.c utils/utils.c)

build/test_webp: core/fp_webp.c core/fp_webp.h tests/test_webp.c $(WEBP_SRC)
	mkdir -p build
	$(CC) -std=c99 -O2 -DHAVE_CONFIG_H -Wall -Wextra -Wno-unused-parameter -Icore -Ivendor/libwebp/src -Ivendor/libwebp core/fp_webp.c tests/test_webp.c $(WEBP_SRC) -o $@

build/test_news_image: core/fp_news_image.c core/fp_news_image.h tests/test_news_image.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_news_image.c tests/test_news_image.c -o $@

build/test_http: core/fp_http.c core/fp_http.h tests/test_http.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_http.c tests/test_http.c -o $@

build/test_guest: core/fp_guest.c core/fp_guest.h core/fp_document.c tests/test_guest.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_guest.c core/fp_document.c tests/test_guest.c -o $@

build/test_frame: core/fp_frame.c core/fp_frame.h tests/test_frame.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_frame.c tests/test_frame.c -lz -o $@

build/test_document: core/fp_document.c core/fp_document.h tests/test_document.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_document.c tests/test_document.c -o $@

build/test_compose: core/fp_compose.c core/fp_compose.h core/fp_document.c core/fp_document.h tests/test_compose.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_compose.c core/fp_document.c tests/test_compose.c -o $@

build/test_qms: core/fp_qms.c core/fp_qms.h core/fp_document.c core/fp_document.h tests/test_qms.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_qms.c core/fp_document.c tests/test_qms.c -o $@

build/test_text: core/fp_text.c core/fp_text.h tests/test_text.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_text.c tests/test_text.c -o $@

build/test_forum: core/fp_forum.c core/fp_forum.h core/fp_text.c core/fp_document.c tests/test_forum.c tests/fixtures/index.reply tests/fixtures/forum.reply tests/fixtures/topic.reply
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_forum.c core/fp_text.c core/fp_document.c tests/test_forum.c -o $@

build/test_bbcode: core/fp_bbcode.c core/fp_bbcode.h tests/test_bbcode.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_bbcode.c tests/test_bbcode.c -o $@

build/test_session: core/fp_session.c core/fp_session.h core/fp_tls.c core/fp_tls.h core/fp_document.c core/fp_frame.c core/fp_auth.c core/fp_client.c core/fp_resolve.c tests/test_session.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_session.c core/fp_tls.c core/fp_document.c core/fp_frame.c core/fp_auth.c core/fp_client.c core/fp_resolve.c tests/test_session.c -lz -lssl -lcrypto -pthread -o $@

build/test_tls_client: core/fp_session.c core/fp_tls.c core/fp_document.c core/fp_frame.c core/fp_resolve.c core/fp_client.c core/fp_auth.c tests/tls_client.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_session.c core/fp_tls.c core/fp_document.c core/fp_frame.c core/fp_resolve.c core/fp_client.c core/fp_auth.c tests/tls_client.c -lz -lssl -lcrypto -pthread -o $@

build/test_theme_settings: core/fp_theme_settings.c core/fp_theme_settings.h tests/test_theme_settings.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_theme_settings.c tests/test_theme_settings.c -o $@

build/test_news_body: core/fp_news_body.c core/fp_news_body.h core/fp_news_article.c core/fp_bbcode.c core/fp_text.c tests/test_news_body.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_news_body.c core/fp_news_article.c core/fp_bbcode.c core/fp_text.c tests/test_news_body.c -o $@

build/test_news_article: core/fp_news_article.c core/fp_news_article.h core/fp_text.c core/fp_text.h core/fp_bbcode.c core/fp_bbcode.h tests/test_news_article.c tests/fixtures/news_article.html
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_news_article.c core/fp_text.c core/fp_bbcode.c tests/test_news_article.c -o $@

build/test_tls_split: core/fp_tls.c core/fp_tls.h tests/test_tls_split.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_tls.c tests/test_tls_split.c -lssl -lcrypto -pthread -o $@

build/test_resolve: core/fp_resolve.c core/fp_resolve.h tests/test_resolve.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_resolve.c tests/test_resolve.c -pthread -o $@

clean:
	rm -rf build

# this optional probe connects to the public service without an account
integration-probe: core/fp_session.c core/fp_tls.c core/fp_document.c core/fp_frame.c tools/guest_probe.c
	mkdir -p build
	$(CC) $(CFLAGS) -Icore core/fp_session.c core/fp_tls.c core/fp_document.c core/fp_frame.c tools/guest_probe.c -lz -lssl -lcrypto -o build/guest_probe
	./build/guest_probe

core-ios:
	bash scripts/build_core.sh

network-ios:
	bash scripts/build_network_ios.sh

app:
	bash scripts/build_app.sh

ipa: app
	bash scripts/package_ipa.sh

ipa-signed: ipa
	bash scripts/sign_ipa.sh

deb: app
	bash scripts/build_deb.sh

# shapka

**native 4pda forum client, ios 5 and later, armv7 and arm64, one ipa**

> [!NOTE]
> version `v1.0.0-stable`. nothing has been run on a device or a simulator by the build.

## devices

- ios 5-6: armv7
- ios 7 and later: armv7, arm64
- the look follows material 3 expressive: tonal surfaces around the 4pda blue, Rubik, large rounded shapes, spring motion; drawn without system bars so it is the same on every ios version

## features

- forum sections, topic lists, messages with paging, login and settings
- bottom bar: news, forums, favorites, settings; each tab keeps its own navigation stack
- lists page by 30 topics or by the posts-per-page setting; swipe left or right, or use the page bar (the page number opens a jump dialog); the first strip of the screen is left to the swipe back
- the first post of a topic comes with every page of the server; on later pages it is a collapsed card
- screens keep their content while a reload runs; a failed reload shows a message over it; an answer that is no longer the newest request is dropped by serial number
- theme: modern or classic with blue ios 5 and 6 style bars, each in light or dark; the material effect setting hides the animated corner wave in the modern theme
- guests read forums and topics without an account

## messages

- laid out on up to two workers, drawn in tiles
- up to four image fetches and decodes in flight, at most two decodes at once; images are decoded at the size they are shown and cached up to 8 MB; avatars are cropped to a circle while decoding
- a bbcode image gets a placeholder until its header is read; up to 32 pixels each way it sits in the line of text, a larger one takes a block of its own proportions and the message is laid out again
- image attachments, bbcode images and direct https image links open in a zoomable viewer; direct links with a separate caption stay as links
- `4pda.to/forum` topics and forums open inside the app, other links in the system browser
- announcements open through `fn`; inline attachments use the file id of `[attachment="id:name"]`
- a post menu can insert its markup as a quote in a reply
- the post header shows the karma of the author and the rating of the post; the post menu rates a post (`fk`, plus or minus once per member), raises or lowers the karma of the author with a reason (`mr`) and lists who rated the post
- links to other pages open in an in-app web view, a forum topic or forum reached from it opens as a native screen

## account

- signed in, a topic reply goes through `fp`; tapping a post offers a private dialog with its author through `qp`
- qms: the messages button opens contacts and dialogs, loads the latest 60 messages and can request earlier ones; messages show raw forum markup
- file attachments: `fa` resolves the address, the file goes to `Documents`, then the open-in menu; `Documents` is shared through file sharing
- downloads need https, are limited to 1 GiB, at most three at once, and the system must trust the download host
- reply and qms drafts are kept per account and destination and removed after a send
- favorites follow the account: the star adds or removes the topic on the server (`fm`), the tab reads the server list (`mf`, windows of 30, at most 500) on every visit and on pull to refresh; each member has a separate copy on the device, a list is never shown to another account; a removal the server refuses leaves the row and shows the error
- as a guest, favorite topics stay on the device; news favorites are always on the device
- if the keychain cannot be read the error is logged and the client continues as a guest; a failed account save is reported and the session is closed

## news

- the `sl` and `sa` commands of the 4pda app protocol load the news list and full articles; the last valid list is cached on the device
- article pictures and previews use their 4pda https addresses and need the site to permit the request; a browser link remains available on failure

## network

- tls websocket to `app.4pda.to:993` through openssl with `resources/trust/roots.pem` (Mozilla-derived, notes next to it)
- login needs verified tls; if the websocket is unreachable only public read operations use the direct guest route found in the android client, it carries only validated public forum and news reads, never passwords or login keys
- `fp_tls` can split the hello into six byte pieces with a 12 ms gap (`split_hello`) for a network that reads the server name out of one segment; verification is unchanged and no caller turns it on at the moment

## layout

- `core/`: portable c, host tested
  - `fp_frame`, `fp_document`, `fp_session`, `fp_tls`, `fp_auth`, `fp_client`: app protocol framing, document parser, websocket session, verified tls, login
  - `fp_resolve`, `fp_http`, `fp_news_http`, `fp_guest`: dns, bounded http/1.x framing, the https news fetch, the guest route
  - `fp_text` (windows-1251, escapes and html entities to utf-8), `fp_forum` (typed parsers for `fi`, `fs`, `fr`, `mf`, `fa`, `fk`), `fp_bbcode` (markup to a flat node list), `fp_compose` (request arguments of `fp`, `qp`, `fk`, `mr` and qms replies, text in windows-1251), `fp_qms`
  - `fp_news_article`, `fp_news_body`, `fp_news_image`, `fp_webp`: news page blocks, `sa` bodies, og:image, webp decoding (libwebp from `vendor/`)
  - `fp_theme_settings`: reads the stored theme mode and style as classic or modern, light or dark; mode 3 stays the classic light theme
- `app/lifecycle/`: `main.m`
- `app/net/`: `FPNetwork` (one connection on a serial queue), `FPApi` (on-demand connect, requests, two bounded parse queues, forum index cache on disk)
- `app/model/`: immutable value objects built from the replies
- `app/ui/`: `FPTheme`, `FPChrome`, `FPListKit`, `FPPostLayout` (CoreText), `FPPostViews` (tiled body view), screens, `FPScreenController`
- `resources/fonts/`: Rubik regular, medium, bold, with its licence
- `resources/ui-icons/`: icons from exteria and exteraless, sources in its README
- `resources/icon-source.png`: `python3 tools/make_icons.py` makes the app icons and launch images (needs pillow, removes the black padding of the source)

## paths

- forum index cache: `Library/Caches/forum-index.reply`
- news list cache: `Library/Caches/news-feed.reply`
- downloads: `Documents`
- login key: keychain, service `com.pageflip.shapka.account`
- settings, drafts, reading positions and the device copy of favorites: `NSUserDefaults`

## install

the build makes a signed ipa, `build/ios-core/Shapka-v1.0.0-stable.ipa`. sign the executable with `packaging/entitlements.plist`: without it ios 6 answers the keychain with -25308 and the login key cannot be saved.

```bash
unzip Shapka-v1.0.0-stable.ipa
scp -r Payload/Shapka.app root@<device-ip>:/Applications/
ssh root@<device-ip> 'chown -R mobile:wheel /Applications/Shapka.app; su mobile -c uicache'
```

bundle id: `com.pageflip.shapka`

## build

```bash
make test
make ipa-signed
```

`make ipa` stops at `Shapka-unsigned.ipa`. `ipa-signed` signs with `ldid` and checks that `Info.plist` and the file name agree on the version.

needs `FP_IOS_TC FP_IOS_SDK_V7 FP_IOS_SDK_V64 FP_OPENSSL_V7 FP_OPENSSL_V64`; `FP_IOS_BUILD` moves the output, `FP_VERSION` sets the name.

host tests need python 3, zlib, openssl headers and the openssl command. they use local sockets, a temporary tls certificate and replies captured from the public service as guest (`tests/fixtures`). `make integration-probe` is an optional guest request to `app.4pda.to:993`.

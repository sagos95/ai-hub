#!/usr/bin/env bats
# Unit tests for extract_post_id() in time-helpers.sh

setup() {
    # SCRIPT_DIR is consumed by helpers for cache path resolution; safe default.
    SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
    # shellcheck source=../scripts/time-helpers.sh
    source "$BATS_TEST_DIRNAME/../scripts/time-helpers.sh"
}

@test "raw 26-char post_id passes through unchanged" {
    result=$(extract_post_id "18grnyo6dxxnf6y46qp8eo5bze")
    [ "$result" = "18grnyo6dxxnf6y46qp8eo5bze" ]
}

@test "permalink URL yields post_id" {
    result=$(extract_post_id "https://dodobrands.time-messenger.ru/dodo-brands/pl/18grnyo6dxxnf6y46qp8eo5bze")
    [ "$result" = "18grnyo6dxxnf6y46qp8eo5bze" ]
}

@test "permalink with ?query yields post_id without query" {
    result=$(extract_post_id "https://example.time-messenger.ru/team/pl/abc123def456ghi789jkl0mnpq?foo=bar")
    [ "$result" = "abc123def456ghi789jkl0mnpq" ]
}

@test "permalink with #fragment yields post_id without fragment" {
    result=$(extract_post_id "https://example.time-messenger.ru/team/pl/zyx987wvu654tsr321qpo0nmlk#section")
    [ "$result" = "zyx987wvu654tsr321qpo0nmlk" ]
}

@test "URL without /pl/ falls through unchanged" {
    result=$(extract_post_id "https://example.time-messenger.ru/team/channels/town-square")
    [ "$result" = "https://example.time-messenger.ru/team/channels/town-square" ]
}

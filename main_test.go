package main

import (
    "testing"
)

func TestDummy(t *testing.T) {
    got := 2 + 2
    want := 4

    if got != want {
        t.Errorf("got %d, want %d", got, want)
    }
}

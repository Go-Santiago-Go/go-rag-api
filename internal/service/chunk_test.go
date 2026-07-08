package service

import (
	"reflect"
	"testing"
)

func TestChunk(t *testing.T) {
	tests := []struct {
		name    string
		text    string
		size    int
		overlap int
		want    []string
	}{
		{"clean multi-chunk walk", "abcdefghij", 4, 1, []string{"abcd", "defg", "ghij"}},
		{"exact fit, no remainder", "abcdef", 3, 0, []string{"abc", "def"}},
		{"text shorter than size", "abc", 10, 2, []string{"abc"}},
		{"empty text", "", 4, 1, nil},
		{"multi-byte runes stay intact", "héllo", 2, 0, []string{"hé", "ll", "o"}},
		{"overlap >= size degrades safely", "abcd", 2, 5, []string{"ab", "cd"}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Chunk(tt.text, tt.size, tt.overlap)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("Chunk(%q, %d, %d) = %#v, want %#v",
					tt.text, tt.size, tt.overlap, got, tt.want)
			}
		})
	}
}

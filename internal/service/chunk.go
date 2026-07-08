package service

// Chunk splits text into overlapping passages of at most size runes, each
// starting size-overlap runes after the previous. Overlap keeps an idea that
// straddles a boundary intact in at least one chunk. Splitting on runes, not
// bytes, prevents cutting a multi-byte UTF-8 character in half.
//
// The loop advances by size-overlap, so that stride must stay positive or start
// never moves. Chunk defends that invariant: a non-positive size yields no
// chunks, and an overlap that meets or exceeds size is clamped to zero (a
// no-overlap walk) rather than looping forever.
func Chunk(text string, size, overlap int) []string {
	if size <= 0 {
		return nil
	}
	if overlap < 0 || overlap >= size {
		overlap = 0
	}
	runes := []rune(text)
	var chunks []string
	for start := 0; start < len(runes); start += size - overlap {
		end := min(start+size, len(runes))
		chunks = append(chunks, string(runes[start:end]))
		if end == len(runes) {
			break
		}
	}
	return chunks
}

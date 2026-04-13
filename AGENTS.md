# Penguin Agent Notes

## Commit Style

- Group commits by logical groups of changes
- Prefer colourful, high-signal commit subjects when they fit the change.
- Emojis are encouraged when they add meaning instead of noise.
- Prefer commit subjects in the style of `🚀 feat(area): concise description`
- Commit bodies should read well in Markdown:
  - concise technical descriptions
  - short paragraphs or flat bullets are preferred
  - inline code should be used for important symbols such as `run_daemon()`
- Call out important functions, APIs, or hot-path symbols when they explain the change well.
- When a change spans runtime behavior and verification/docs, prefer separate commits if that keeps the history clearer.
- Keep commit messages intentional and specific even when they are playful.

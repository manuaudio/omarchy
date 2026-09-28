-- Emacs binds the Super chords itself (Doom maps Super+C and Super+V to yank and
-- paste), and its Ctrl+C and Ctrl+V are a command prefix and page down, so the
-- universal clipboard shortcuts pass the Super chord through untranslated.
o.window("(emacs|Emacs)", { tag = "+native-super-clipboard" })

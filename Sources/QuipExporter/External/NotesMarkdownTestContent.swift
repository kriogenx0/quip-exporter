extension NotesWriter {
    static func markdownTestContent(title: String) -> String {
        """
        # \(title)

        ## Formatting
        Normal **bold**, *italic*, ~~strikethrough~~.

        ## Blockquote
        > This is a block quote paragraph.

        ## Code
        `let x = 42 // inline code`

        ## Checklist
        - [x] Checked item
        - [ ] Unchecked item

        ## Numbered List
        1. First item
        2. Second item

        ## Bullet List
        - Bullet one
        - Bullet two

        ## Table
        | Header 1 | Header 2 |
        |----------|----------|
        | Cell A   | Cell B   |

        ## Horizontal Rule
        ---
        """
    }
}

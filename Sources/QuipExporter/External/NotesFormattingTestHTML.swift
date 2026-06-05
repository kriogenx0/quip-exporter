extension NotesWriter {
    static func formattingTestHTML(dateStr: String) -> String {
        """
        <html><body>\
        <h1>Test \u{2014} \(dateStr)</h1>\
        <p>Normal <b>bold</b>, <i>italic</i>, <u>underline</u>, <s>strikethrough</s>.</p>\
        <h2>Colors</h2>\
        <p><span style="color:#e03131;">Red</span> \
        <span style="color:#2f9e44;">Green</span> \
        <span style="color:#1971c2;">Blue</span> \
        <span style="background-color:#ffe066;">Highlighted</span></p>\
        <h2>Link</h2>\
        <p><a href="https://quip.com">Quip website</a></p>\
        <h2>Blockquote</h2>\
        <blockquote type="cite">This is a block quote paragraph.</blockquote>\
        <h2>Code</h2>\
        <p><tt>let x = 42 // inline code</tt></p>\
        <h2>Checklist</h2>\
        <ul><li>[x] Checked item</li><li>[ ] Unchecked item</li></ul>\
        <h2>Numbered List</h2>\
        <p>1. First item</p><p>2. Second item</p>\
        <h2>Bullet List</h2>\
        <ul><li>Bullet one</li><li>Bullet two</li></ul>\
        <h2>Table</h2>\
        <table><tr><th>Header 1</th><th>Header 2</th></tr><tr><td>Cell A</td><td>Cell B</td></tr></table>\
        <h2>Horizontal Rule</h2>\
        <p>\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}\u{2014}</p>\
        </body></html>
        """
    }
}

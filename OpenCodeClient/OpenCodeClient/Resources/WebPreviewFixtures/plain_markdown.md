# Plain Markdown Baseline

This fixture verifies that ordinary Markdown renders correctly.

## Section Two

Here is a paragraph with **bold text**, *italic text*, and some `inline code`. You can also combine ***bold italic*** when needed.

### Subsection Three

An unordered list:

- First item
- Second item
  - Nested item A
  - Nested item B
- Third item

An ordered list:

1. Step one
2. Step two
3. Step three

## A GFM Table

| Name    | Role      | Active |
| ------- | --------- | ------ |
| Alice   | Engineer  | Yes    |
| Bob     | Designer  | No     |
| Carol   | Manager   | Yes    |

## A Fenced Code Block

```python
def greet(name: str) -> str:
    """Return a friendly greeting."""
    return f"Hello, {name}!"

print(greet("world"))
```

## A Link and a Blockquote

Visit the [project docs](https://example.com/docs) for more detail.

> This is a blockquote. It should be visually offset from the body text,
> typically with a left border and indentation.

That is the end of the baseline fixture.

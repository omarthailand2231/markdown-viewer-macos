---
title: Everything
tags: [markdown, test]
---

# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6

Setext Heading
==============

Setext Two
----------

## Heading 2

Plain *em*, _em_, **strong**, __strong__, ***both***, ~~strike~~, `code`, ``a`b``.
Escapes: \*not em\* and \# not heading, entities &copy; &amp; &lt;tag&gt;.
Backslash hard break\
next line.

Links: [inline](https://example.com), [titled](https://example.com "Title"), [ref link][ref], <https://autolink.example>, bare https://bare.example.com and www.example.org, [other doc](other.md), [anchor](#heading-2).

[ref]: https://reference.example

Images: ![local pixel](pixel.png) ![remote](https://example.com/remote.png)

> Quote level 1
>
> > Nested quote
>
> ```
> code in quote
> ```

- Item one
  - Nested two
    - Nested three
- Item four

3. Start at three
4. Four

- loose item one

- loose item two

- [ ] open task
- [x] done task
- [X] done upper
  - [ ] nested task

| Left | Center | Right | None |
|:-----|:------:|------:|------|
| **b** | `c` | [l](https://x.y) | a \| pipe |
| | empty first | 3 | |

| Only | Header |
|------|--------|

***
___

```swift
let html = "<b>" + "&" // escaped
```

~~~
tilde fence
~~~

    indented code <x>

<details>
<summary>Raw HTML block</summary>

Inside details.
</details>

Inline <kbd>Ctrl</kbd> + <kbd>C</kbd>.

<p align="center"><img src="pixel.png" width="32" alt="raw html image"> <img src="https://example.com/x.png?a=1&amp;b=2" alt="remote raw"></p>

ภาษาไทย สวัสดีครับ 🎉 emoji

Footnote ref[^1].

[^1]: The footnote.

> [!NOTE]
> A note callout.

> [!WARNING]
> Careful.

Second footnote use[^long].

[^long]: Long note with **bold**
    and a continued line.

```
[^1] inside a fence stays literal
```

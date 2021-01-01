+++
title = "PHP 8 - Attributes: How to (de)serialize data structures smoothly"
date = 2021-01-01
[taxonomies]
tags = ["PHP", "PHP 8", "Serde", "Rust"]
+++

With PHP 8 a lot of long awaited features came. I'm really excited about `match` expressions, constructor property promotion, named arguments, but I dare to say that many aren't that excited about attributes as I'm. I've heard that many even asked "Yeah, what about them? What are they for?" and that's what I want to show you. First of all I'm - after that long struggle - glad that they have the same syntax as in Rust! It's just great in my opinion and one syntax tweak less I have to think about.
But what can you do with them? You may have [read about them](https://stitcher.io/blog/attributes-in-php-8) on [stitcher.io](https://stitcher.io/) which gave a neat first impression what they are capable of. But I'm more interested in my long journey of serializing / deserializing data structures. In Rust there is this amazing tool called [serde](https://serde.rs/) with which you can serialize and deserialize from and into many different data formats like json, toml etc. I've never found a smiliar tool in PHP. Sure, you can use the Zend Hydrator or it's brethren (e.g. from Symfony) but they aren't that smooth in my opinion. Let's just look on how serde handles it:

```rust
#[derive(Deserialize)]
struct Foo {
    #[serde(default = 42)]
    #[serde(rename = "id")]
    #[serde(alias = "Id")]
    #[serde(alias = "ID")]
    my_id: u32
}

let foo: Foo = serde_json::from_str("{ \"id\": 23 }").unwrap();
```
<small>Of course we could smash those attributes in one long statement</small>

I often thought about implementing it in such way in PHP, but each time I instantly discarded that idea as soon as it came to my mind. That's because prior to PHP 8 you had to use doc-comments. And parsing them or even relying on such a textual structure was just painful. But now, with attributes in php 8? Worth considering! Let's see how we _could_ translate this to modern PHP:

```php
<?php

final class Foo {
    use Json\Deserialize;

    #[Rename("id")]
    #[Default(42)]
    #[Alias("Id")]
    #[Alias("ID")]
    public int $myId;
}

$foo = Foo::deserialize("{ \"id\": 23 }");
```

To keep this post short, we will only focus on those 3 attributes:
 - renaming: let us define, how the field should be named instead of the current property name
 - default-values: which value should be assigned, if the value is not initialized?
 - alias: which other names - for whatever reasons - could the field be called?

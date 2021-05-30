+++
title = "PHP 8 - Attributes: How to (de)serialize data structures smoothly"
date = 2021-01-01
[taxonomies]
tags = ["PHP", "PHP 8", "Serde", "Rust"]
+++

With PHP 8 a lot of long awaited features were release. I'm really excited about `match` expressions, constructor property promotion, named arguments, but I dare to say that many aren't that excited about attributes as I am. I've heard that many even asked "Yeah, what about them? What are they for?" and that's what I want to show you. First of all I'm - after that long struggle - glad that they have the same syntax as in Rust! It's just great in my opinion and one syntax tweak less I have to think about.
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

I often thought about implementing it the same way in PHP, but each time I instantly discarded that idea as soon as it came to my mind. That's because prior to PHP 8 you had to use doc-comments. And parsing them or even relying on such a textual structure was just painful. But now, with attributes in php 8? Worth considering! Let's see how we _could_ translate this to modern PHP:

```php
<?php

final class Foo {
    use Json\Deserialize;

    #[Rename(deserialize: "id")]
    #[DefaultValue(42)]
    #[Alias("Id")]
    #[Alias("ID")]
    public int $myId;
}

$foo = Foo::deserialize("{ \"id\": 23 }");
```

<small>It's `DefaultValue` instead of just `Default` because the later is a reserved keyword in PHP</small>

So first of all, we need some attributes (also called _annotation_'s in other languages):

```php
<?php

namespace Dgame\Serde\Annotation;

use Attribute;

#[Attribute(Attribute::TARGET_PROPERTY | Attribute::IS_REPEATABLE)]
final class Alias
{
    public function __construct(public string $alias)
    {
    }
}

#[Attribute(Attribute::TARGET_PROPERTY)]
final class DefaultValue
{
    public function __construct(public mixed $value = null)
    {
    }
}

#[Attribute(Attribute::TARGET_PROPERTY)]
final class Rename
{
    public function __construct(public ?string $deserialize = null, public ?string $serialize = null)
    {
    }
}
```

To define your own attributes, you have to annotate them with `#[Attribute]`. If you do that, you can smash them on everything you want: properties, classes, parameters etc. But we want to limit this only to properties. Therefore, we have to specify the attribute-flags (the first and only constructor argument) as such: `Attribute::TARGET_PROPERTY`. What about `Attribute::IS_REPEATABLE`? Normally we cannot annotate something with the same attribute twice, but in the case of `Alias` we want to allow that, therefore we have to extend the attribute-flags (which is a bit-mask) with `Attribute::IS_REPEATABLE`.

With that in mind, we can do the interpretation with specialized `Deserializers`:

```php
<?php

namespace Dgame\Serde\Deserializer;

interface Deserializer
{
    public function deserialize(mixed $input): mixed;

    public function getDefaultValue(): mixed;
}
```

A `Deserializer` accepts a `mixed` argument and translates it to the wanted type. For example for `int`:

```php
<?php

namespace Dgame\Serde\Deserializer;

final class IntDeserializer implements Deserializer
{
    public function deserialize(mixed $input): int
    {
        assert(is_numeric($input));

        return (int) $input;
    }

    public function getDefaultValue(): int
    {
        return 0;
    }
}
```

<small>To keep it simple and short, we just use an `assert`.</small>

We need `Deserializer`s for each built-in type and for _user defined objects_. The later is somewhat special, because a class contains properties which have their own types and probably their own annotations. So we need to cover that:

```php
<?php

namespace Dgame\Serde\Deserializer;

use ReflectionClass;
use stdClass;

final class UserDefinedObjectDeserializer implements Deserializer
{
    public function __construct(private ReflectionClass $reflection)
    {
        foreach ($reflection->getProperties() as $property) {
            // TODO: Here is where the "magic" happens
        }
    }

    public function getDefaultValue(): ?object
    {
        return null;
    }

    public function deserialize(mixed $input): object
    {
        assert($input instanceof stdClass);

        $object = $this->reflection->newInstanceWithoutConstructor();
        // TODO: deserialize the $input and hydrate the $object

        return $object;
    }
}
```

You may have wondered about `assert($input instanceof stdClass);`.
If we want to e.g. deserialize json, we have two options: either decode it as an associative array or as a `stdClass`. Most of the time we want to have an associative array but in this case, we really want a `stdClass`. The reason for that is simple: if we had an assoc. array, we could not easily differentiate between real (assoc.) array and objects. But with a `stdClass` we can: each object is a `stdClass` and each array is an array.

No let's implement the initialization in the constructor:

```php
<?php

namespace Dgame\Serde\Deserializer;

use ReflectionClass;
use stdClass;

final class UserDefinedObjectDeserializer implements Deserializer
{
    /**
     * @var array<string, Deserializer>
     */
    private array $propertyDeserializer = [];
    /**
     * @var array<string, string[]>
     */
    private array $alias = [];

    public function __construct(private ReflectionClass $reflection)
    {
        foreach ($reflection->getProperties() as $property) {
            // first of all, we assume that the property is of type "mixed"
            $propertyDeserializer = new MixedValueDeserializer();

            /** @var ReflectionNamedType|null $type */
            $type = $property->getType();
            if ($type !== null) {
                $propertyDeserializer = $this->makeTypeDeserializer($property, $type) ?? $propertyDeserializer;
            }

            $propertyName = $property->getName();
            // TODO: handle Alias-, Rename- and DefaultValue-Attributes

            $this->setDeserializer($propertyName, $propertyDeserializer);
        }
    }

    private function makeTypeDeserializer(ReflectionProperty $property, ReflectionNamedType $type): ?Deserializer
    {
        return DeserializerReflectionTypeFactory::fromReflectionNamedType($type);
    }

    // ...
}
```

```php
<?php

namespace Dgame\Serde\Deserializer;

use ReflectionClass;
use ReflectionNamedType;
use UnexpectedValueException;

final class DeserializerReflectionTypeFactory
{
    public static function parse(string $type): Deserializer
    {
        return match ($type) {
            'string' => throw new UnexpectedValueException('string'),
            'int' => new IntDeserializer(),
            'float' => throw new UnexpectedValueException('float'),
            'bool' => throw new UnexpectedValueException('bool'),
            'array' => throw new UnexpectedValueException('array'),
            'object', 'stdClass' => throw new UnexpectedValueException('object'),
            'mixed' => throw new UnexpectedValueException('mixed'),,
            default => new UserDefinedObjectDeserializer(new ReflectionClass($type))
        };
    }

    public static function fromReflectionNamedType(ReflectionNamedType $type): Deserializer
    {
        // TODO: ReflectionUnionType

        if ($type->isBuiltin()) {
            $deserializer = self::parse($type->getName());
        } else {
            $deserializer = new UserDefinedObjectDeserializer(new ReflectionClass($type->getName()));
        }

        // TODO: $type->allowsNull()

        return $deserializer;
    }
}
```

<small>We group `object` and `stdClass`, because in both cases we cannot determine, which type it should be</small>

As you can see, we still miss some `Deserializer`, we have to handle union-types (also a new PHP 8 feature) and what we'll do, if the type is nullable.

First of all, let's handle nullable types. We need a `DefaultValueDeserializer` which takes another `Deserializer` and a default value which is used, if `$input` is `null`:

```php
<?php

namespace Dgame\Serde\Deserializer;

final class DefaultValueDeserializer implements Deserializer
{
    public function __construct(private Deserializer $deserializer, private mixed $default = null)
    {
        $this->default ??= $this->deserializer->getDefaultValue();
    }

    public function deserialize(mixed $input): mixed
    {
        if ($input === null) {
            return $this->default;
        }

        return $this->deserializer->deserialize($input);
    }

    public function getDefaultValue(): mixed
    {
        return $this->default;
    }
}
```

```php
<?php

namespace Dgame\Serde\Deserializer;

use ReflectionClass;
use ReflectionNamedType;
use UnexpectedValueException;

final class DeserializerReflectionTypeFactory
{
    // ...

    public static function fromReflectionNamedType(ReflectionNamedType $type): Deserializer
    {
        // TODO: ReflectionUnionType

        if ($type->isBuiltin()) {
            $deserializer = self::parse($type->getName());
        } else {
            $deserializer = new UserDefinedObjectDeserializer(new ReflectionClass($type->getName()));
        }

        if ($type->allowsNull()) {
            return new DefaultValueDeserializer($deserializer);
        }

        return $deserializer;
    }
}
```

That's that. Now let's speak about union types. Union types are just pipe separated types like `int|string` which means, the variable can be **either** `int` or `string`. And how can we handle that? Thankfully, PHP's Reflections are really good and of course we have a `ReflectionUnionType`:

```php
<?php

namespace Dgame\Serde\Deserializer;

use ReflectionClass;
use ReflectionNamedType;
use UnexpectedValueException;

final class DeserializerReflectionTypeFactory
{
    // ...

    public static function fromReflectionNamedType(ReflectionNamedType $type): Deserializer
    {
        if ($type instanceof ReflectionUnionType) {
            return self::fromReflectionUnionType($type);
        }

       // ...
    }

    private static function fromReflectionUnionType(ReflectionUnionType $type): Deserializer
    {
        /** @var Deserializer[] $deserializers */
        $deserializers = [];
        foreach ($type->getTypes() as $ty) {
            $deserializers[] = self::fromReflectionNamedType($ty);
        }

        return new ChainedDeserializer(...$deserializers);
    }
}
```

A _ChainedDeserializer_ is a `Deserializer`, that accepts multiple `Deserializer` which are applied successively to the `$input`. Also, it returns the first non-null default-value (or null if there is none):

```php
<?php

namespace Dgame\Serde\Deserializer;

final class ChainedDeserializer implements Deserializer
{
    /**
     * @var Deserializer[]
     */
    private array $deserializers;

    public function __construct(Deserializer ...$deserializers)
    {
        $this->deserializers = $deserializers;
    }

    public function getDefaultValue(): mixed
    {
        foreach ($this->deserializers as $deserializer) {
            $value = $deserializer->getDefaultValue();
            if ($value !== null) {
                return $value;
            }
        }

        return null;
    }

    public function deserialize(mixed $input): mixed
    {
        foreach ($this->deserializers as $deserializer) {
            $input = $deserializer->deserialize($input);
        }

        return $input;
    }
}
```

So far so good. What's missing are the other built-in type `Deserializer`

 - StringDeserializer
 - FloatDeserializer
 - BoolDeserializer
 - ObjectDeserializer
 - MixedValueDeserializer

They're somewhat identical to the `IntDeserializer` so I don't show each of them here. If you want, you can take a peek at the [Github Project](https://github.com/Dgame/php-serde).

With that, all that's left are the both TODO's:

 - `// TODO: handle Alias-, Rename- and DefaultValue-Attributes`:
 - `// TODO: deserialize the $input and hydrate the $object`

## Handle Alias-, Rename- and DefaultValue-Attributes
```php
<?php

// ...

final class UserDefinedObjectDeserializer implements Deserializer
{
    /**
     * @var array<string, Deserializer>
     */
    private array $propertyDeserializer = [];
    /**
     * @var array<string, string[]>
     */
    private array $alias = [];

    public function __construct(private ReflectionClass $reflection)
    {
        foreach ($reflection->getProperties() as $property) {
            // ...

            $propertyName = $property->getName();
            foreach ($property->getAttributes(Alias::class) as $attribute) {
                /** @var Alias $annotation */
                $annotation = $attribute->newInstance();

                $this->setAlias($annotation->alias, $propertyName);
            }

            foreach ($property->getAttributes(Rename::class) as $attribute) {
                /** @var Rename $annotation */
                $annotation = $attribute->newInstance();
                if (!empty($annotation->deserialize)) {
                    $this->setAlias($annotation->deserialize, $propertyName);
                }
            }

            foreach ($property->getAttributes(DefaultValue::class) as $attribute) {
                /** @var DefaultValue $annotation */
                $annotation           = $attribute->newInstance();
                $propertyDeserializer = new DefaultValueDeserializer($propertyDeserializer, $annotation->value);
            }

            $this->setDeserializer($propertyName, $propertyDeserializer);
        }
    }

    public function setDeserializer(string $propertyName, Deserializer $deserializer): void
    {
        $this->propertyDeserializer[$propertyName] = $deserializer;
    }

    public function setAlias(string $alias, string $propertyName): void
    {
        $this->alias[$propertyName][] = $alias;
    }

    // ...
}
```

As you can see, with e.g. `$property->getAttributes(Alias::class)` we get all `Alias`-attributes of that property and then we can use their content. Simple, right? With that done, we can apply attributes to any properties.

## Deserialize the $input and hydrate the $object

```php
<?php

// ...
final class UserDefinedObjectDeserializer implements Deserializer
{
    // ...

    public function deserialize(mixed $input): object
    {
        assert($input instanceof stdClass);

        $object = $this->reflection->newInstanceWithoutConstructor();
        foreach ($this->propertyDeserializer as $propertyName => $deserializer) {
            if (!$this->reflection->hasProperty($propertyName)) {
                continue;
            }

            $property = $this->reflection->getProperty($propertyName);
            $value = $this->extractValue($input, $propertyName);
            if ($value === null && $property->hasDefaultValue()) {
                continue;
            }

            $value = $deserializer->deserialize($value);
            if ($value !== null || $this->isNullValidArgument($property)) {
                $property->setAccessible(true);
                $property->setValue($object, $value);
            }
        }

        return $object;
    }

    private function isNullValidArgument(ReflectionProperty $property): bool
    {
        $type = $property->getType();
        if ($type === null) {
            return true;
        }

        return $type->allowsNull();
    }

    private function extractValue(stdClass $input, string $name): mixed
    {
        $names = [$name, ...$this->alias[$name] ?? []];
        foreach ($names as $alias) {
            if (!property_exists($input, $alias)) {
                continue;
            }

            return $input->{$alias};
        }

        return null;
    }
}
```

Let's get over it piece by piece:

```php
<?php
// ...
if (!$this->reflection->hasProperty($propertyName)) {
    continue;
}
// ...
```

First of all, if, for some reason, the property isn't there, we do nothing.

```php
<?php
// ...
$value = $this->extractValue($input, $propertyName);
// ...
```

We need to extract the value of the `$input` with which the current property should be assigned.

```php
<?php
// ...
$property = $this->reflection->getProperty($propertyName);
if ($value === null && $property->hasDefaultValue()) {
    continue;
}
// ...
```

If the belonging value in `$input` is `null` and the property has an default-value, we keep that default-value.

```php
<?php
// ...
$value = $deserializer->deserialize($value);
if ($value !== null || $this->isNullValidArgument($property)) {
    $property->setAccessible(true);
    $property->setValue($object, $value);
}
// ...
```

At last, we deserialize the value with the corresponding `Deserializer`. If the value is non-null or the property allows null, we assign it. Otherwise, it'll stay uninitialized.

## What about arrays?

Arrays are a bit special. Since PHP does not support generics (yet), we have no way of knowing, what specific types are stored inside of them. In Languages like Rust, Java etc. you have `Vec<T>` or `List<T>` where `T` is the specific type. Also, in PHP an array can hold multiple absolute different types. So for simplicity, we just support arrays which have values of the same type. But how do we specify, which type it is?

Consider this:

```php
<?php

final class Bar
{
    use Json\Deserialize;

    /**
     * @var Foo[] $children
     */
    private array $children;
}

$bar = Bar::deserialize("{ \"children\": [ { \"id\": 42 } ] }");
```

We have no way of knowing, that `$children` is a array of `Foo`. Even if we would rely on the doc-comments, it's optional and there is no way to ensure it's correct. Therefore we need to add the `ArrayOf` _Attribute_:

```php
<?php

namespace Dgame\Serde\Annotation;

use Attribute;

#[Attribute(Attribute::TARGET_PROPERTY)]
final class ArrayOf
{
    public function __construct(public string $type)
    {
    }
}
```

With that, we also have to introduce the `ArrayDeserializer`
```php
<?php

namespace Dgame\Serde\Deserializer;

use stdClass;

final class ArrayDeserializer implements Deserializer
{
    public function __construct(private Deserializer $deserializer)
    {
    }

    public function deserialize(mixed $input): array
    {
        // we allow stdClass so that we can support assoc. array
        if ($input instanceof stdClass) {
            $input = (array) $input;
        }

        assert(is_array($input));

        $output = [];
        foreach ($input as $key => $value) {
            if (is_array($value)) {
                $value = $this->deserialize($value);
            }

            $output[$key] = $this->deserializer->deserialize($value);
        }

        return $output;
    }

    public function getDefaultValue(): array
    {
        return [];
    }
}
```

and change the `makeTypeDeserializer` method from `UserDefinedObjectDeserializer`:

```php
<?php

// ...

final class UserDefinedObjectDeserializer implements Deserializer
{
    // ...
    private function makeTypeDeserializer(ReflectionProperty $property, ReflectionNamedType $type): ?Deserializer
    {
        if ($type->isBuiltin() && $type->getName() === 'array') {
            $propertyDeserializer = null;
            foreach ($property->getAttributes(ArrayOf::class) as $attribute) {
                /** @var ArrayOf $default */
                $annotation = $attribute->newInstance();

                $propertyDeserializer = new ArrayDeserializer(DeserializerReflectionTypeFactory::parse($annotation->type));
            }

            return $propertyDeserializer;
        }

        return DeserializerReflectionTypeFactory::fromReflectionNamedType($type);
    }
    // ...
}
```

With that we can define our purpose just fine:

```php
<?php
final class Bar
{
    use Json\Deserialize;

    /**
     * @var Foo[] $children
     */
     #[ArrayOf(Foo::class)]
    private array $children;
}

$bar = Bar::deserialize("{ \"children\": [ { \"id\": 42 } ] }");
```

And that's that!

## Bringing it all together

We have everything we need (if you're missing something, take a peek at [the Github-Project](https://github.com/Dgame/php-serde)). So, let's test it:

```php
<?php

// usings etc.

final class A
{
    private int $id;
}

$udoa = new UserDefinedObjectDeserializer(new ReflectionClass(A::class));
$udoa->setAlias('Id', 'id');
$udoa->setAlias('ID', 'id');
$udoa->setDeserializer('id', new DefaultValueDeserializer(new IntDeserializer(), default: 1337));
print_r($udoa->deserialize((object) []));
print_r($udoa->deserialize((object) ['id' => 1]));
print_r($udoa->deserialize((object) ['Id' => 2]));
print_r($udoa->deserialize((object) ['ID' => 3]));
```

Output:
```
A Object
(
    [id:A:private] => 1337
)
A Object
(
    [id:A:private] => 1
)
A Object
(
    [id:A:private] => 2
)
A Object
(
    [id:A:private] => 3
)
```

Nice! One more with the `ArrayDeserializer`:

```php
<?php

// usings etc.

final class B
{
    private array $as = [1, 2, 3];
}

$udob = new UserDefinedObjectDeserializer(new ReflectionClass(B::class));
$udob->setDeserializer('as', new DefaultValueDeserializer(new ArrayDeserializer($udoa)));
print_r($udob->deserialize((object) []));
print_r($udob->deserialize((object) ['as' => []]));
print_r($udob->deserialize((object) ['as' => [(object) ['id' => 1]]]));
print_r($udob->deserialize((object) ['as' => [(object) ['id' => 1], (object) ['Id' => 2]]]));
print_r($udob->deserialize((object) ['as' => ['a' => (object) ['id' => 1], 'b' => (object) ['Id' => 2]]]));
```

Output:
```
B Object
(
    [as:B:private] => Array
        (
            [0] => 1
            [1] => 2
            [2] => 3
        )

)
B Object
(
    [as:B:private] => Array
        (
        )

)
B Object
(
    [as:B:private] => Array
        (
            [0] => A Object
                (
                    [id:A:private] => 1
                )

        )

)
B Object
(
    [as:B:private] => Array
        (
            [0] => A Object
                (
                    [id:A:private] => 1
                )

            [1] => A Object
                (
                    [id:A:private] => 2
                )

        )

)
B Object
(
    [as:B:private] => Array
        (
            [a] => A Object
                (
                    [id:A:private] => 1
                )

            [b] => A Object
                (
                    [id:A:private] => 2
                )

        )

)
```

That looks promising! But, it's still nasty to assembly these `Deserializer` by hand. What I want is, to use a trait to inject the deserialize-functionality into the specific class.
Here's how we _could_ do it:

```php
<?php

namespace Dgame\Serde\Deserializer;

use ReflectionClass;
use stdClass;

trait Deserialize
{
    private static ?UserDefinedObjectDeserializer $deserializer = null;

    public static function deserialize(stdClass $input): static
    {
        if (self::$deserializer === null) {
            self::$deserializer = new UserDefinedObjectDeserializer(new ReflectionClass(static::class));
        }

        return self::$deserializer->deserialize($input);
    }
}
```

With that we would be able to do our examples without configuring all of the `Deserializer`. And if we want to deserialize json or another format? well, we _could_ just use another `Deserialize`-trait in another namespace which delegates the deserialize process to the "main" `Deserialize`-trait:

```php
<?php

namespace Dgame\Serde\Json;

use stdClass;

trait Deserialize
{
    use \Dgame\Serde\Deserializer\Deserialize;

    public static function deserializeJson(string $content): ?static
    {
        $input = json_decode($content, associative: false, flags: JSON_THROW_ON_ERROR);

        return $input instanceof stdClass ? self::deserialize($input) : null;
    }
}
```

And with that we can test it:

```php
<?php

// usings etc.

final class C
{
    use Deserialize;

    #[DefaultValue(1337)]
    #[Alias("Id")]
    #[Alias("ID")]
    private int $id;
}

print_r(C::deserializeJson('{ }'));
print_r(C::deserializeJson('{ "id": 1 }'));
print_r(C::deserializeJson('{ "Id": 2 }'));
print_r(C::deserializeJson('{ "ID": 3 }'));
```

Output:
```
C Object
(
    [id:C:private] => 1337
)
C Object
(
    [id:C:private] => 1
)
C Object
(
    [id:C:private] => 2
)
C Object
(
    [id:C:private] => 3
)
```

Perfect! Seems like we're done.

## Summary

We just made a simple but reliable deserializer thanks to the PHP 8 attributes. The `Serializer` components are a lot easier, therefore I wont cover that here. I hope you enjoyed that little ride and that you experienced how cool the new PHP 8 features are!
The finished project can be found [on Github](https://github.com/Dgame/php-serde).

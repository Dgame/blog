+++
title = "Use Docker in WSL 2 and watch it on Windows 10"
date = 2020-12-31
[taxonomies]
tags = ["WSL", "WSL 2", "Windows", "Windows 10", "Docker", "PHP", "Rust", "Zola", "Ansible"]
+++

At the beginning of the year I've started a new job where I will mainly program in PHP and I have to use either Windows 10 or MacOS instead of my usual Manjaro setup. Since I'm still using Windows 10 from time to time (merely to play games) I'm more familiar with it. It's not that bad of a thing. Since WSL (and especially WSL 2) it's totally fine to work under Windows 10 in my opinion. I've adjusted my [Ansible Playbook](https://github.com/Dgame/dgame-system) to work under WSL with the distribution Ubuntu 18.04 and 20.04 which made it a lot easier as well.

I came to work with Docker in 2018 and in the past few months (I have way to much time since the 2. Lockdown) I've came to the conclusion, that I don't like to install things like php, mysql, sqlite, apache, rust, cargo etc. locally. Most of the time, I'll use Docker for most of the projects anyway, so why bother? Just use a docker-container with php, mysql, apache or rust installed. That was the idea. But I had a little trouble to get it working under WSL 2. WSL 2 is a wonderful thing in my opinion. I can use it as if I would use a real Linux distribution. So let's see what we can do.

# PHP

On manjaro I've often used `php -S 127.0.0.1:8000` to quickly test or debug php projects and I've heard that if you start a webserver under WSL2, you can access it on the Windows 10 Host! So let's do that. First of all, install php and execute `php --version`. I've got this:

```
$ php --version
PHP 7.4.3 (cli) (built: Oct  6 2020 15:47:56) ( NTS )
Copyright (c) The PHP Group
Zend Engine v3.4.0, Copyright (c) Zend Technologies
    with Zend OPcache v7.4.3, Copyright (c), by Zend Technologies
```

Now, let's create a new folder with a small php file in it:
```php
<?php

phpinfo();
```

If we now execute `php -S 127.0.0.1:8000` on our WSL 2 terminal and visit `https://localhost:8000` we get ... nothing. Took me a few minutes to figure out that you have to use `0.0.0.0` instead of the usual `127.0.0.1` :rolling_eyes:. But with that it works fine. We execute `php -S 0.0.0.0:8000` and if we visit `https://localhost:8000` again, we get to see the expected php version 7.4.3

![](php-wsl-localhost.png)

That's neat! But what we originally wanted was no to install php on our machine, but to use a docker container instead. So let's do that.

[Project on Github](https://github.com/Dgame/php-docker-localhost)

# Rust

Well, as you may have noticed, this Blog runs with zola (at the bottom of each site is a hint) which is a static-site generator, written in Rust. I like Rust. It's my favorite programming language since 2015 and I doubt that will change in the next couple of years. In my old job I had the opportunity to work with Rust, especially in combination with AWS (all of your AWS-Lambdas were written in Rust). But for now, that doesn't seem possible. But the time will tell! Anyways, since I've moved to work under WSL 2 with Ubuntu 20.04, I've wanted write blog posts here too instead of switching to my manjaro machine. But I didn't wanted to install zola on Ubuntu. My goal was to use it as well in a Docker-Container. So how can we do that?

[Project on Github](https://github.com/Dgame/blog)

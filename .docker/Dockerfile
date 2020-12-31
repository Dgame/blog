FROM archlinux as zola-base

ARG USER_ID=1000

RUN pacman -Sy && pacman -S zola --noconfirm
RUN groupadd -g $USER_ID www-data ; \
    useradd -u $USER_ID -g $USER_ID www-data

RUN mkdir /blog
WORKDIR /blog

RUN chown -R www-data:www-data /blog

USER www-data

FROM zola-base as builder

COPY . /blog
RUN zola build

FROM nginx:stable-alpine
RUN mv /usr/share/nginx/html/index.html /usr/share/nginx/html/old-index.html
COPY --from=builder /site/public/ /usr/share/nginx/html/
EXPOSE 80

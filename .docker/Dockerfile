FROM archlinux as zola-base
RUN pacman -Sy && pacman -S zola --noconfirm
RUN mkdir /blog
WORKDIR /blog

FROM zola-base as builder
COPY . /blog
RUN zola build

FROM nginx:stable-alpine
RUN mv /usr/share/nginx/html/index.html /usr/share/nginx/html/old-index.html
COPY --from=builder /site/public/ /usr/share/nginx/html/
EXPOSE 80

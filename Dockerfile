ARG ruby_version=2.1.10

FROM ruby:${ruby_version}-alpine as build

RUN apk add --no-cache make gcc git libc-dev

WORKDIR /root
COPY Gemfile Gemfile.lock ./

WORKDIR /root/vendor/bundle/ruby
RUN bundle install --no-cache --deployment --without development && \
      rm -rf ./*/cache ./*/gems/*/spec/* ./*/gems/*/tests/*


FROM ruby:${ruby_version}-alpine

ARG kubectl_version=1.19.4
ARG version=DEV

LABEL org.opencontainers.image.title="Stackbuilder" \
  org.opencontainers.image.vendor="TIM Group" \
  org.opencontainers.image.source="https://github.com/tim-group/stackbuilder" \
  org.opencontainers.image.version="${version}"

ADD https://storage.googleapis.com/kubernetes-release/release/v${kubectl_version}/bin/linux/amd64/kubectl /usr/local/bin/kubectl

RUN chmod +x /usr/local/bin/kubectl && \
      apk add --no-cache git openssh-client

WORKDIR /root

COPY --from=build /root /root
COPY --from=build /usr/local/bundle /usr/local/bundle

COPY bin /usr/local/bin/
COPY lib /usr/local/lib/site_ruby/timgroup
COPY mcollective_plugins /usr/share/mcollective/plugins/mcollective


ENV RUBYLIB=/usr/local/lib/site_ruby/timgroup
ENTRYPOINT ["bundle", "exec", "/usr/local/bin/stacks"]

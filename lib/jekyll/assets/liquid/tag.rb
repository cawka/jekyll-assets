# Frozen-string-literal: true
# Copyright: 2012-2015 - MIT License
# Encoding: utf-8

require "fastimage"

module Jekyll
  module Assets
    module Liquid
      class Tag < ::Liquid::Tag
        require_relative "tag/proxies"
        require_relative "tag/proxied_asset"
        require_relative "tag/defaults"
        require_relative "tag/parser"
        attr_reader :args

        class << self
          public \
            :new
        end

        class AssetNotFoundError < StandardError
          def initialize(asset)
            super "Could not find the asset `#{asset}'"
          end
        end

        #

        AcceptableTags = %W(
          img
          image
          javascript
          asset_source
          stylesheet
          asset_path
          style
          asset
          css
          js
        )

        #

        Tags = {
          "css" => %Q{<link type="text/css" rel="stylesheet" href="%s"%s>},
          "js"  => %Q{<script type="text/javascript" src="%s"%s></script>},
          "img" => %Q{<img src="%s"%s>}
        }

        #

        Alias = {
          "image" => "img",
          "stylesheet" => "css",
          "javascript" => "js",
          "style" => "css"
        }

        #

        def initialize(tag, args, tokens)
          @tokens = tokens
          @tag = from_alias(tag)
          @args = Parser.new(args, @tag)
          @og_tag = tag
          super
        end

        # NOTE: We only attach to the regenerator if you are using digested
        #   assets, otherwise we forego any association with it so that we keep
        #   your builds ultra fast, this is ideal in dev.  Disable digests and
        #   let us process independent so the entire site isn't regenerated
        #   because of a single asset change.

        def render(context)
          args = Parser.parse_liquid(@args, context)
          site = context.registers[:site]
          page = context.registers.fetch(:page, {})
          sprockets = site.sprockets
          page = page["path"]

          asset = find_asset(sprockets)
          add_as_jekyll_dependency(site, sprockets, page, asset)
          process_tag(args, sprockets, asset)
        rescue => e
          capture_and_out_error \
            site, e
        end

        #

        private
        def from_alias(tag)
          Alias.has_key?(tag) ? Alias[tag] : tag
        end

        #

        private
        def process_tag(args, sprockets, asset)
          sprockets.used.add(asset) unless @tag == "asset_source"
          Defaults.set_defaults_for!(@tag, args ||= {}, asset)
          build_html(args, sprockets, asset)
        end

        #

        private
        def build_html(args, sprockets, asset, path = get_path(sprockets, asset))
          if @tag == "asset_path"
            return path

          elsif @tag == "asset" || @tag == "asset_source"
            return asset.to_s

          elsif args.has_key?(:data) && args[:data].has_key?(:uri)
            return Tags[@tag] % [
              asset.data_uri, Parser.to_html(args)
            ]

          else
            return Tags[@tag] % [
              path, Parser.to_html(args)
            ]
          end
        end

        #

        private
        def get_path(sprockets, asset)
          sprockets.prefix_path(sprockets.digest?? asset.digest_path : \
            asset.logical_path)
        end

        #

        private
        def add_as_jekyll_dependency(site, sprockets, page, asset)
          if page && sprockets.digest?
            site.regenerator.add_dependency(
              site.in_source_dir(page), site.in_source_dir(asset.logical_path)
            )
          end
        end

        #

        private
        def find_asset(sprockets)
          file, _sprockets = @args[:file], @args[:sprockets] ||= {}
          if !(out = sprockets.find_asset(file, _sprockets))
            raise AssetNotFoundError, @args[:file]
          else
            out.liquid_tags << self
            !args.has_proxies?? out : ProxiedAsset.new( \
              out, @args, sprockets, self)
          end
        end

        # There is no guarantee that Jekyll will pass on the error for some
        # reason (unless you are just booting up) so we capture that error and
        # always output it, it can lead to some double errors but I would
        # rather there be a double error than no error.

        private
        def capture_and_out_error(site, error)
          if error.is_a?(Sass::SyntaxError)
            file = error.sass_filename.gsub(/#{Regexp.escape(site.source)}\//, "")
            Jekyll.logger.error(%Q{Error in #{file}:#{error.sass_line}  #{error}})
          else
            Jekyll.logger.error \
              "", error.to_s
          end

          raise error
        end
      end
    end
  end
end

Jekyll::Assets::Liquid::Tag::AcceptableTags.each do |tag|
  Liquid::Template.register_tag tag, Jekyll::Assets::Liquid::Tag
end

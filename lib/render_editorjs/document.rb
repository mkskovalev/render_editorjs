# frozen_string_literal: true

module RenderEditorjs
  class Document
    include ActionView::Helpers::OutputSafetyHelper
    require 'nokogiri'

    attr_reader :renderer, :content, :errors

    ALLOWED_PROTOCOLS = ['http', 'https', 'mailto']

    def initialize(content, renderer = RenderEditorjs::DefaultRenderer.new)
      @renderer = renderer
      @content = content.is_a?(Hash) ? content : parse_json(content)
      @errors = []
    end

    def valid?
      return false unless valid_renderer?

      validate_blocks

      @errors.empty?
    end

    def render
      return "" unless valid_renderer?
    
      rendered_content = safe_join(
        content["blocks"].map do |block|
          block_renderer = block_renderers(block["type"])
          next unless block_renderer

          block_renderer.render(block["data"])
        end.compact
      )

      sanitize_links(rendered_content)
    end

    private

    def sanitize_links(html_content)
      return html_content unless html_content

      fragment = Nokogiri::HTML::DocumentFragment.parse(html_content)

      fragment.css('a').each do |link|
        href = link['href']
        next unless href

        if href =~ /^\s*javascript:/i || href =~ /^\s*data:/i
          link.remove_attribute('href')
        else
          begin
            uri = URI.parse(href)
            unless uri.scheme.nil? || ALLOWED_PROTOCOLS.include?(uri.scheme)
              link.remove_attribute('href')
            end
          rescue URI::InvalidURIError
            link.remove_attribute('href')
          end
        end
      end

      safe_join(fragment.children)
    end

    def valid_renderer?
      renderer.validator(content).validate!
    rescue JSON::Schema::ValidationError => e
      @errors << e.message

      false
    end

    def validate_blocks
      content["blocks"].each do |block|
        block_renderer = block_renderers(block["type"])
        next unless block_renderer

        validator = block_renderer.validator(block["data"])
        @errors << validator.errors unless validator.valid?
      end
    end

    def block_renderers(block_type)
      @block_renderers ||= {}
      @block_renderers[block_type] ||= renderer.mapping[block_type]
    end

    def parse_json(content)
      JSON.parse(content)
    rescue JSON::ParserError
      nil
    end
  end
end

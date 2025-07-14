module Reissue
  class Markdown
    def self.parse(changelog)
      new(changelog).to_h
    end

    def initialize(changelog)
      @changelog = changelog
      @versions = {}
      @header = nil
      @parts = []
    end

    def parse
      return unless @header.nil? && @versions.empty?

      header, *chunks = @changelog.split(/^## /)

      @header = Header.new(header)
      @versions = Array(chunks).map { |part| Version.new(part) }
    end

    def to_h
      parse
      @header.to_h.merge("versions" => @versions.map(&:to_h))
    end

    class Header
      def initialize(chunk)
        @chunk = chunk.to_s
        @title = nil
        @preamble = nil
      end

      def parse
        return unless @title.nil? && @preamble.nil?

        scanner = StringScanner.new(@chunk.dup << "\n")
        scanner.scan(/# ([\w\s]+)$/)
        @title = scanner[1].to_s.strip
        # the rest of the text is the preamble
        @preamble = scanner.rest.strip
      end

      def to_h
        parse
        {
          "title" => @title,
          "preamble" => @preamble
        }
      end
    end

    class Version
      def initialize(chunk)
        @chunk = chunk
        @version = nil
        @date = nil
        @changes = []
      end

      def parse
        return unless @version.nil? && @date.nil? && @changes.empty?
        # the first line contains the version and date
        scanner = StringScanner.new(@chunk) << "\n"
        scanner.scan(/\[?(.[^\]]+)\]? - (.+)$/)
        @version = scanner[1].to_s.strip
        @date = scanner[2].to_s.strip || "Unreleased"

        # the rest of the text is the changes
        @changes = scanner.rest.strip.split("### ").reject(&:empty?).map { |change| Change.new(change) }
      end

      def to_h
        parse
        {
          "version" => @version,
          "date" => @date,
          "changes" => @changes.inject({}) { |h, change| h.merge(change.to_h) }
        }
      end
    end

    class Change
      def initialize(chunk)
        @chunk = chunk
        @type = nil
        @changes = []
      end

      def parse
        return unless @type.nil? && @changes.empty?
        scanner = StringScanner.new(@chunk) << "\n"
        scanner.scan(/([\w\s]+)$/)

        @type = scanner[1].to_s.strip

        # the rest of the text are the changes
        @changes = scanner
          .rest
          .strip
          .split(/^-/m)
          .map { |change| change.strip.gsub(/^- /m, "") }
          .reject(&:empty?)
      end

      def to_h
        parse
        {
          @type => @changes.map { |change| change.split("\n").map(&:strip).join("\n  ") }
        }
      end
    end
  end
end

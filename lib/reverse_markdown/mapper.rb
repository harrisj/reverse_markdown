module ReverseMarkdown
  class Mapper
    attr_accessor :raise_errors
    attr_accessor :log_enabled, :log_level
    attr_accessor :li_counter
    attr_accessor :github_style_code_blocks
    attr_accessor :theaders
    attr_accessor :taligns
    attr_accessor :new_table

    def initialize(opts={})
      self.log_level   = :info
      self.log_enabled = true
      self.li_counter  = 0
      self.github_style_code_blocks = opts[:github_style_code_blocks] || false
      self.taligns = []
      self.theaders = 0
      self.new_table = :no # :yes, :no, :thead
    end

    def process_root(element)
      return '' if element.nil?

      markdown = process_element(element)  # recursively process all elements to get full markdown

      # Extract github style code blocks
      extractions = {}
      markdown.gsub!(%r{```.*?```}m) do |match|
        md5 = Digest::MD5.hexdigest(match)
        extractions[md5] = match
        "{code-block-extraction-#{md5}}"
      end

      markdown = markdown.split("\n").map do |line|
        if line.match(/^( {4}|\t)/)
          line
        else
          "#{ '  ' if line.match(/^ {2,3}/) }" +
          normalize_whitespace(line).strip +
          "#{ '  ' if line.match(/ {2}$/) }"
        end
      end.join("\n")

      markdown.gsub!(/\n{3,}/, "\n\n")

      # Insert pre block extractions
      markdown.gsub!(/\{code-block-extraction-([0-9a-f]{32})\}/){ extractions[$1] }

      markdown
    end

    def process_element(element)
      output = ''
      if element.text?
        text = process_text(element)
        if output.end_with?(' ') && text.start_with?(' ')
          output << text.lstrip
        else
          output << text
        end
      else
        output << opening(element).to_s

        markdown_chunks = element.children.map { |child| process_element(child) }
        remove_adjacent_whitespace!(markdown_chunks)
        output << markdown_chunks.join

        output << ending(element).to_s
      end
      output
    end

    private

    # removes whitespace-only chunk if the previous chunk ends with whitespace
    def remove_adjacent_whitespace!(chunks)
      (chunks.size - 1).downto(1).each do |i|
        chunk = chunks[i]
        previous_chunk = chunks[i-1]
        chunks.delete_at(i) if chunk == ' ' && previous_chunk.end_with?(' ')
      end
    end

    def opening(element)
      parent = element.parent ? element.parent.name.to_sym : nil
      case element.name.to_sym
        when :html, :body
          ""
        when :li
          indent = '  ' * [(element.ancestors('ol').count + element.ancestors('ul').count - 1), 0].max
          if parent == :ol
            "#{indent}#{self.li_counter += 1}. "
          else
            "#{indent}- "
          end
        when :table
          self.new_table = :yes
          "\n\n"
        when :thead # && 
          # puts "thead"
          self.new_table = :thead
          if parent == :table
            self.taligns = []
            self.theaders = 0
            '| '
          else
            ''
          end
        when :tbody
          # puts "tbody"
          self.new_table = :yes unless self.new_table == :thead
          ''
        # when :tr
        #   self.trow = []
        # when :td, :th
        #   if self.trow == []
        #     trow << element.name.to_sym << sel
        when :tr
          if parent == :thead
            if (self.theaders += 1) > 1
              handle_error "malformed table header"
            end
            ''
          elsif parent == :tbody
            #binding.pry
            str = ''
            if self.theaders == 0 && self.new_table == :yes then
              self.new_table = :no
              children = element.children.select { |el| ['td','th'].include? el.name }
              fill = lambda do |with|
                children.flat_map do |el|
                  cs = el['colspan']
                  [with] * ((cs && cs.to_i) || 1)
                end
              end
              str  = "|#{fill.call('   ').join('|')}|\n"
              str += "|#{fill.call('---').join('|')}|\n"
            end
            # binding.pry
            str += '| '
          end
        when :th
          self.taligns << (element['align'] || :left).to_sym
          ''          
        when :pre
          "\n"
        when :ol
          self.li_counter = 0
          "\n"
        when :ul, :root#, :p
          "\n"
        when :div
          "\n"
        when :p
          if element.ancestors.map(&:name).include?('blockquote')
            "\n\n> "
          elsif [nil, :body].include? parent
            is_first = true
            previous = element.previous
            while is_first == true and previous do
              is_first = false unless previous.content.strip == "" || previous.text?
              previous = previous.previous
            end
            is_first ? "" : "\n\n"
          else
            "\n\n"
          end
        when :h1, :h2, :h3, :h4 # /h(\d)/ for 1.9
          element.name =~ /h(\d)/
          "\n" + ('#' * $1.to_i) + ' '
        when :em, :i
          element.text.strip.empty? ? '' : '_' if (element.ancestors('em') + element.ancestors('i')).empty?
        when :strong, :b
          element.text.strip.empty? ? '' : '**' if (element.ancestors('strong') + element.ancestors('b')).empty?
        when :blockquote
          "> "
        when :code
          if parent == :pre
            self.github_style_code_blocks ? "\n```\n" : "\n    "
          else
            " `"
          end
        when :a
          if !element.text.strip.empty? && element['href'] && !element['href'].start_with?('#')
            " ["
          else
            " "
          end
        when :img
          " !["
        when :hr
          "\n* * *\n"
        when :br
          "  \n"
        else
          handle_error "unknown start tag: #{element.name.to_s}"
          ""
      end
    end

    def ending(element)
      parent = element.parent ? element.parent.name.to_sym : nil
      case element.name.to_sym
        when :html, :body, :pre, :hr
          ""
        when :th, :td
          ' |'
        when :tr
          "\n"
        when :p
          "\n\n"
        when :div
          "\n"
        when :table
          "\n"          
        when :thead
          if parent == :table
            (['|'].concat(self.taligns.map do |align|
              case align
                when :left
                  '---|'
                when :center
                  ':-:|'
                when :right
                  '--:|'
              end
            end) << "\n").join('')
          else
            ''
          end
        when :h1, :h2, :h3, :h4 # /h(\d)/ for 1.9
          "\n"
        when :em, :i
          element.text.strip.empty? ? '' : '_' if (element.ancestors('em') + element.ancestors('i')).empty?
        when :strong, :b
          element.text.strip.empty? ? '' : '**' if (element.ancestors('strong') + element.ancestors('b')).empty?
        when :li, :blockquote, :root, :ol, :ul
          "\n"
        when :code
          if parent == :pre
            self.github_style_code_blocks ? "\n```" : "\n"
          else
           '` '
          end
        when :a
          if !element.text.strip.empty? && element['href'] && !element['href'].start_with?('#')
            "](#{element['href']}#{title_markdown(element)})"
          else
            ""
          end
        when :img
          "#{element['alt']}](#{element['src']}#{title_markdown(element)}) "
        else
          handle_error "unknown end tag: #{element.name}"
          ""
      end
    end

    def title_markdown(element)
      title = element['title']
      title ? %[ "#{title}"] : ''
    end

    def process_text(element)
      parent = element.parent ? element.parent.name.to_sym : nil
      case
        when parent == :code
          if self.github_style_code_blocks
            element.text
          else
            element.text.strip.gsub(/\n/,"\n    ")
          end
        else
          normalize_whitespace(escape_text(element.text))
      end
    end

    def normalize_whitespace(text)
      text.tr("\n\t", ' ').squeeze(' ')
    end

    def escape_text(text)
      text.
        gsub('*', '\*').
        gsub('_', '\_')
    end

    def handle_error(message)
      if raise_errors
        raise ReverseMarkdown::ParserError, message
      elsif log_enabled && defined?(Rails)
        Rails.logger.__send__(log_level, message)
      end
    end
  end
end

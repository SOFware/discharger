# frozen_string_literal: true

require "prism"

module Discharger
  module SetupRunner
    class ConditionEvaluator
      class << self
        def evaluate(condition, context = {})
          return true if condition.nil? || condition.strip.empty?
          ast = Prism.parse(condition).value
          raise "Parse error" unless ast
          evaluate_node(ast)
        rescue => e
          log_warning("Condition evaluation failed: #{e.message}")
          false
        end

        private

        def evaluate_node(node)
          case node.type
          when :program_node
            # Evaluate the first statement in the program
            stmts = node.statements
            if stmts && stmts.body.any?
              evaluate_node(stmts.body.first)
            else
              true
            end
          when :statements_node
            # Evaluate the first statement
            if node.body.any?
              evaluate_node(node.body.first)
            else
              true
            end
          when :and_node
            left = evaluate_node(node.left)
            right = evaluate_node(node.right)
            left && right
          when :or_node
            left = evaluate_node(node.left)
            right = evaluate_node(node.right)
            left || right
          when :call_node
            # Handle method calls
            if node.receiver&.type == :constant_read_node
              case node.receiver.name
              when :ENV
                if node.name == :[]
                  ENV[evaluate_node(node.arguments.arguments.first)]
                else
                  raise "Unsafe ENV method: #{node.name}"
                end
              when :File
                case node.name
                when :exist?
                  File.exist?(evaluate_node(node.arguments.arguments.first))
                when :directory?
                  File.directory?(evaluate_node(node.arguments.arguments.first))
                when :file?
                  File.file?(evaluate_node(node.arguments.arguments.first))
                else
                  raise "Unsafe File method: #{node.name}"
                end
              when :Dir
                if node.name == :exist?
                  Dir.exist?(evaluate_node(node.arguments.arguments.first))
                else
                  raise "Unsafe Dir method: #{node.name}"
                end
              else
                raise "Unsafe method call: #{node.receiver.name}.#{node.name}"
              end
            elsif node.receiver&.type == :call_node
              # Handle chained calls like ENV['FOO'] == 'bar'
              if node.name == :==
                left = evaluate_node(node.receiver)
                right = evaluate_node(node.arguments.arguments.first)
                left == right
              elsif node.name == :!=
                left = evaluate_node(node.receiver)
                right = evaluate_node(node.arguments.arguments.first)
                left != right
              else
                raise "Unsafe operator: #{node.name}"
              end
            elsif node.receiver.nil?
              # Method call without receiver (like system)
              raise "Unsafe method call: #{node.name}"
            else
              raise "Unsafe method call: #{node.receiver&.name}.#{node.name}"
            end
          when :constant_read_node
            node.name
          when :string_node
            node.unescaped
          when :true_node # standard:disable Lint/BooleanSymbol
            true
          when :false_node # standard:disable Lint/BooleanSymbol
            false
          when :array_node
            node.elements.map { |el| evaluate_node(el) }
          when :symbol_node
            node.unescaped
          when :integer_node
            node.value
          when :x_string_node
            # Backtick commands - block for security
            raise "Unsafe backtick command"
          when :parentheses_node
            # Evaluate the expression inside parentheses
            evaluate_node(node.body)
          else
            raise "Unsafe node: #{node.type}"
          end
        end

        def log_warning(message)
          if defined?(Rails)
            Rails.logger.warn(message)
          else
            warn("[SetupRunner] #{message}")
          end
        end
      end
    end
  end
end

import Foundation

public struct FormulaEngine {

    // MARK: - Public

    public enum FormulaError: Error, LocalizedError {
        case unexpectedCharacter(Character)
        case unexpectedToken(String)
        case undefinedProperty(String)
        case divisionByZero
        case unexpectedEnd

        public var errorDescription: String? {
            switch self {
            case .unexpectedCharacter(let c): return "Unexpected character: '\(c)'"
            case .unexpectedToken(let t): return "Unexpected token: '\(t)'"
            case .undefinedProperty(let p): return "Undefined property: '\(p)'"
            case .divisionByZero: return "Division by zero"
            case .unexpectedEnd: return "Unexpected end of expression"
            }
        }
    }

    /// Evaluate a formula expression, resolving property references from the values dictionary.
    ///
    /// Supports: `+`, `-`, `*`, `/`, parentheses, number literals, and property names (e.g. `prop_price`).
    public static func evaluate(expression: String, values: [String: Double]) throws -> Double {
        var parser = Parser(tokens: try tokenize(expression), values: values)
        let result = try parser.parseExpression()
        guard parser.isAtEnd else {
            throw FormulaError.unexpectedToken(String(describing: parser.currentToken))
        }
        return result
    }

    // MARK: - Tokenizer

    private enum Token: CustomStringConvertible {
        case number(Double)
        case identifier(String)
        case plus, minus, star, slash
        case leftParen, rightParen

        var description: String {
            switch self {
            case .number(let n): return "\(n)"
            case .identifier(let s): return s
            case .plus: return "+"
            case .minus: return "-"
            case .star: return "*"
            case .slash: return "/"
            case .leftParen: return "("
            case .rightParen: return ")"
            }
        }
    }

    private static func tokenize(_ expression: String) throws -> [Token] {
        var tokens: [Token] = []
        var i = expression.startIndex

        while i < expression.endIndex {
            let c = expression[i]

            if c.isWhitespace {
                i = expression.index(after: i)
                continue
            }

            switch c {
            case "+": tokens.append(.plus); i = expression.index(after: i)
            case "-": tokens.append(.minus); i = expression.index(after: i)
            case "*": tokens.append(.star); i = expression.index(after: i)
            case "/": tokens.append(.slash); i = expression.index(after: i)
            case "(": tokens.append(.leftParen); i = expression.index(after: i)
            case ")": tokens.append(.rightParen); i = expression.index(after: i)
            default:
                if c.isNumber || c == "." {
                    let start = i
                    while i < expression.endIndex && (expression[i].isNumber || expression[i] == ".") {
                        i = expression.index(after: i)
                    }
                    guard let value = Double(expression[start..<i]) else {
                        throw FormulaError.unexpectedToken(String(expression[start..<i]))
                    }
                    tokens.append(.number(value))
                } else if c.isLetter || c == "_" {
                    let start = i
                    while i < expression.endIndex && (expression[i].isLetter || expression[i].isNumber || expression[i] == "_") {
                        i = expression.index(after: i)
                    }
                    tokens.append(.identifier(String(expression[start..<i])))
                } else {
                    throw FormulaError.unexpectedCharacter(c)
                }
            }
        }

        return tokens
    }

    // MARK: - Recursive Descent Parser

    private struct Parser {
        let tokens: [Token]
        let values: [String: Double]
        var pos = 0

        var isAtEnd: Bool { pos >= tokens.count }
        var currentToken: Token? { pos < tokens.count ? tokens[pos] : nil }

        mutating func advance() { pos += 1 }

        // expression = term (('+' | '-') term)*
        mutating func parseExpression() throws -> Double {
            var result = try parseTerm()
            while let token = currentToken {
                switch token {
                case .plus:
                    advance()
                    result += try parseTerm()
                case .minus:
                    advance()
                    result -= try parseTerm()
                default:
                    return result
                }
            }
            return result
        }

        // term = factor (('*' | '/') factor)*
        mutating func parseTerm() throws -> Double {
            var result = try parseFactor()
            while let token = currentToken {
                switch token {
                case .star:
                    advance()
                    result *= try parseFactor()
                case .slash:
                    advance()
                    let divisor = try parseFactor()
                    guard divisor != 0 else { throw FormulaError.divisionByZero }
                    result /= divisor
                default:
                    return result
                }
            }
            return result
        }

        // factor = ('+' | '-') factor | primary
        mutating func parseFactor() throws -> Double {
            guard let token = currentToken else { throw FormulaError.unexpectedEnd }
            switch token {
            case .plus:
                advance()
                return try parseFactor()
            case .minus:
                advance()
                return -(try parseFactor())
            default:
                return try parsePrimary()
            }
        }

        // primary = NUMBER | IDENTIFIER | '(' expression ')'
        mutating func parsePrimary() throws -> Double {
            guard let token = currentToken else { throw FormulaError.unexpectedEnd }
            switch token {
            case .number(let n):
                advance()
                return n
            case .identifier(let name):
                advance()
                guard let value = values[name] else { throw FormulaError.undefinedProperty(name) }
                return value
            case .leftParen:
                advance()
                let result = try parseExpression()
                guard case .rightParen = currentToken else {
                    throw FormulaError.unexpectedToken(currentToken.map(String.init(describing:)) ?? "end")
                }
                advance()
                return result
            default:
                throw FormulaError.unexpectedToken(String(describing: token))
            }
        }
    }
}

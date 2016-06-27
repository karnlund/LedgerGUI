//
//  Parser.swift
//  LedgerGUI
//
//  Created by Chris Eidhof on 23/06/16.
//  Copyright © 2016 objc.io. All rights reserved.
//

import Foundation
import SwiftParsec

struct Date {
    let year: Int
    let month: Int
    let day: Int
}

enum TransactionState: Character {
    case cleared = "*"
    case pending = "!"
}

extension TransactionState: Equatable { }

typealias LedgerDouble = Double // TODO use infinite precision arithmetic

enum PostingOrNote {
    case posting(Posting)
    case note(Note)
}

extension Transaction {
    init(dateStateAndTitle: (Date, TransactionState?, String), comment: Note?, items: [PostingOrNote]) {
        var transactionNotes: [Note] = []
        var postings: [Posting] = []
        
        if let note = comment {
            transactionNotes.append(note)
        }
        
        for postingOrNote in items {
            switch postingOrNote {
            case .posting(let posting):
                postings.append(posting)
            case .note(let note) where postings.isEmpty:
                transactionNotes.append(note)
            case .note(let note):
                postings[postings.count-1].notes.append(note)
            }
        }
        
        self = Transaction(date: dateStateAndTitle.0, state: dateStateAndTitle.1, title: dateStateAndTitle.2, notes: transactionNotes, postings: postings)
    }
}

struct Amount {
    let number: LedgerDouble
    let commodity: String
    init(number: LedgerDouble, commodity: String) {
        self.number = number
        self.commodity = commodity
    }
}

extension Amount: Equatable {}

func ==(lhs: Amount, rhs: Amount) -> Bool {
    return lhs.commodity == rhs.commodity && lhs.number == rhs.number
}

struct Note {
    let comment: String
    init(_ comment: String) {
        self.comment = comment
    }
}

extension Note: Equatable {}

func ==(lhs: Note, rhs: Note) -> Bool {
    return lhs.comment == rhs.comment
}

struct Posting {
    var account: String
    var amount: Amount?
    var notes: [Note]
}

extension Posting {
    init(account: String, amount: Amount? = nil, note: Note? = nil) {
        self = Posting(account: account, amount: amount, notes: note.map { [$0] } ?? [])
    }
}

extension Posting: Equatable { }

func ==(lhs: Posting, rhs: Posting) -> Bool {
    return lhs.account == rhs.account && lhs.amount == rhs.amount
}

struct Transaction {
    var date: Date
    var state: TransactionState?
    var title: String
    var notes: [Note]
    var postings: [Posting]
}

extension Transaction: Equatable { }
func ==(lhs: Transaction, rhs: Transaction) -> Bool {
    return lhs.date == rhs.date && lhs.state == rhs.state && lhs.title == rhs.title && lhs.notes == rhs.notes && lhs.postings == rhs.postings
}

func pair<A,B>(_ x: A) -> (B) -> (A,B) {
    return { y in (x,y) }
}

extension Date: Equatable {}
func ==(lhs: Date, rhs: Date) -> Bool {
    return lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
}

extension Character {
    
    func isMemberOfCharacterSet(_ set: CharacterSet) -> Bool {
        let normalized = String(self).precomposedStringWithCanonicalMapping
        let unicodes = normalized.unicodeScalars
        
        guard unicodes.count == 1 else { return false }
        return set.contains(UnicodeScalar(unicodes.first!.value))
    }
    
    var isSpace: Bool {
        return isMemberOfCharacterSet(.whitespaces)
    }
    
    var isNewlineOrSpace: Bool {
        return isMemberOfCharacterSet(.whitespacesAndNewlines)
    }
}

let naturalString: GenericParser<String, (), String> = StringParser.digit.many1.map { digits in String(digits) }
let naturalWithCommaString = (StringParser.digit <|> StringParser.character(",")).many1.map( { digitsAndCommas in String(digitsAndCommas.filter { $0 != "," }) })

let natural: GenericParser<String, (), Int> = naturalString.map { Int($0)! }

func monthDay(_ separator: Character) -> GenericParser<String, (), (Int, Int)> {
    let separatorInt = StringParser.character(separator) *> natural
    return GenericParser.lift2( { ($0, $1)} , parser1: separatorInt, parser2: separatorInt)
}

extension Date {
    static let parser:  GenericParser<String, (), Date> =
       { y in { m, d in Date(year: y, month: m, day: d) } } <^> natural <*> (monthDay("/") <|> monthDay("-"))
}

func lexeme<A>(_ parser: GenericParser<String,(), A>) -> GenericParser<String, (), A> {
    return parser <* spaceWithoutNewline.many
}

func lexline<A>(_ parser: GenericParser<String,(), A>) -> GenericParser<String, (), A> {
    return parser <* StringParser.oneOf(" \t").many <* StringParser.newLine
}

let noNewline: GenericParser<String,(),Character> = StringParser.noneOf("\n\r") // TODO use real newline stuff
let spaceWithoutNewline: GenericParser<String,(),Character> = StringParser.character(" ")

let spacer = (spaceWithoutNewline *> spaceWithoutNewline) <|> StringParser.tab

let noteStart: StringParser = StringParser.character(";")
let trailingNoteStart = spacer *> noteStart
let noteBody = ({Note(String($0))} <^> noNewline.many)
let trailingNote = lexeme(trailingNoteStart) *> noteBody
let note = lexeme(noteStart) *> noteBody

let transactionCharacter = trailingNoteStart.noOccurence *> noNewline

let transactionState = StringParser.character("*").map { _ in TransactionState.cleared } <|> StringParser.character("!").map { _ in TransactionState.pending }

let transactionHelper: GenericParser<String, (), String> = transactionCharacter.many.map { String($0) }
let transactionTitle: GenericParser<String, (), (Date, TransactionState?, String)> =
    GenericParser.lift3( { ($0, $1, $2) }, parser1: lexeme(Date.parser), parser2: lexeme(transactionState.optional), parser3: transactionHelper)

let commodity: GenericParser<String, (), String> = StringParser.string("USD") <|> StringParser.string("EUR") <|> StringParser.string("$")
let double: GenericParser<String, (), LedgerDouble> = GenericParser.lift2( { x, fraction in // todo name x
    guard let fraction = fraction else { return Double(x)! }
    return Double("\(x).\(fraction)")!
}, parser1: naturalWithCommaString, parser2: (StringParser.character(".") *> naturalString).optional)


let noSpace: GenericParser<String, (), Character> = StringParser.satisfy { !$0.isNewlineOrSpace }
let singleSpace: GenericParser<String, (), Character> = (spaceWithoutNewline <* noSpace.lookAhead).attempt

let amount: GenericParser<String, (), Amount> =
    GenericParser.lift2({ Amount(number: $1, commodity: $0) }, parser1: lexeme(commodity), parser2: double) <|>
    GenericParser.lift2(Amount.init, parser1: lexeme(double), parser2: commodity)

let account = GenericParser.lift2({ String( $1.prepending($0) ) }, parser1: noSpace, parser2: (noSpace <|> singleSpace).many)

let posting: GenericParser<String, (), Posting> = GenericParser.lift3(Posting.init, parser1: lexeme(account), parser2: amount.optional, parser3: trailingNote.optional)

let commentStart: GenericParser<String, (), Character> = StringParser.oneOf(";#%|*")

let comment: GenericParser<String, (), Note> = commentStart *> spaceWithoutNewline.many *> ( { Note(String($0)) } <^> noNewline.many)

let postingOrNote = PostingOrNote.note <^> lexeme(note) <|> PostingOrNote.posting <^> lexeme(posting)

extension GenericParser {
    public func lazySeparatedBy1<Separator>(_ separator: GenericParser<StreamType, UserState, Separator>) -> GenericParser<StreamType, UserState, [Result]> {

        return self >>- { result in

            (separator *> self).attempt.many >>- { results in

                let rs = results.prepending(result)
                return GenericParser<StreamType, UserState, [Result]>(result: rs)

            }

        }

    }
}



let transaction: GenericParser<String, (), Transaction> =
    GenericParser.lift3(Transaction.init, parser1: transactionTitle, parser2: lexline(trailingNote.optional), parser3: (spaceWithoutNewline.many1 *> postingOrNote).lazySeparatedBy1(StringParser.newLine))

struct AccountDirective {
    let name: String
}

func ==(lhs: AccountDirective, rhs: AccountDirective) -> Bool {
    return lhs.name == rhs.name
}
extension AccountDirective: Equatable {}

let accountDirective: GenericParser<String, (), AccountDirective> =
    lexeme(StringParser.string("account")) *> (AccountDirective.init <^> account)


indirect enum Expression: Equatable {
    case infix(`operator`: String, lhs: Expression, rhs: Expression)
    case number(LedgerDouble)
    case amount(Amount)
    case ident(String)
    case regex(String)
    case string(String)
}

func ==(lhs: Expression, rhs: Expression) -> Bool {
    switch (lhs, rhs) {
    case let (.infix(op1, lhs1, rhs1), .infix(op2, lhs2, rhs2)) where op1 == op2 && lhs1 == lhs2 && rhs1 == rhs2:
        return true
    case let (.number(x), .number(y)) where x == y: return true
    case let(.amount(x), .amount(y)) where x == y: return true
    case let(.ident(x), .ident(y)) where x == y: return true
    case let(.regex(x), .regex(y)) where x == y: return true
    case let(.string(x), .string(y)) where x == y: return true
    default: return false
    }
}

func binary(_ name: String, assoc: Associativity = .left) -> Operator<String, (), Expression> {
    let opParser = lexeme(StringParser.string(name).attempt) >>- { name in // todo: is the attempt really necessary?
        return GenericParser(result: {
            Expression.infix(operator: name, lhs: $0, rhs: $1)
        })
    }
    return .infix(opParser, assoc)

}

func delimited(by character: Character) -> GenericParser<String,(),String> {
    let delimiter = StringParser.character(character)
    return delimiter *> ({ String($0) } <^> StringParser.anyCharacter.manyTill(delimiter))
}

let regex: GenericParser<String,(),String> = delimited(by: "/")

let string = delimited(by: "\"") <|> delimited(by: "'")

let ident = { String($0) } <^> (StringParser.alphaNumeric <|> StringParser.character("_")).many1

let opTable: OperatorTable<String, (), Expression> = [
    [ binary("*"), binary("/")],
    [ binary("+"), binary("-")],
    [ binary("=="), binary("!="), binary("<"), binary("<="), binary(">"), binary(">="), binary("=~"), binary("!~")],
    [ binary("&&")],
    [ binary("||")],

]

let openingParen: StringParser = lexeme(StringParser.character("("))
let closingParen: StringParser = lexeme(StringParser.character(")"))

let primitive: GenericParser<String,(),Expression> =
    Expression.amount <^> amount.attempt <|>
    Expression.number <^> double <|>
    Expression.regex <^> regex <|>
    Expression.string <^> string <|>
    Expression.ident <^> ident

struct AutomatedTransaction {
    enum TransactionType {
        case regex(String)
        case expr(Expression)
    }

    var type: TransactionType
    var postings: [Posting]
}

let expression = opTable.makeExpressionParser { expression in
    expression.between(openingParen, closingParen) <|>
        lexeme(primitive) <?> "simple expression"

    } <?> "expression"
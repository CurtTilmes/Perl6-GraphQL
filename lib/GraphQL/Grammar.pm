#use Grammar::Tracer;

unit grammar GraphQL::Grammar;

#
# Adapted expect() and error() from
# https://perlgeek.de/blog-en/perl-6/2017-007-book-parse-errors.html
#

method expect($what)
{
    self.error("expected $what");
}

method error($msg)
{
    my $parsed-so-far = self.target.substr(0, self.pos);
    my @lines = $parsed-so-far.lines;
    die "Parse failure: $msg at line @lines.elems()" ~
        ("after '@lines[*-1]'" if @lines.elems > 1);
}

token SourceCharacter { <[\x[0009]\x[000A]\x[000D]\x[0020]..\x[FFFF]]> }

token Ignored
{ <UnicodeBOM> | <WhiteSpace> | <LineTerminator> | <Comma> }

token UnicodeBOM { \x[FEFF] }

token WhiteSpace { \x[0009] | \x[0020] }

token LineTerminator
{ \x[000A] | \x[000D]<!before \x[000A]> | \x[000D]\x[000A] }

token Comment { '#' <.CommentChar>* }

token CommentChar { <SourceCharacter><!after <LineTerminator>> }

token Comma { ',' }

# Lexical Tokens

token Name { <[_A..Za..z]><[_0..9A..Za..z]>* }

token IntValue { <.IntegerPart> }

token IntegerPart
{ [ <.NegativeSign>? 0 | <.NegativeSign>? <.NonZeroDigit> <.Digit>* ] }

token NegativeSign { '-' }

token Digit { <[0..9]> }

token NonZeroDigit { <[1..9]>}

token FloatValue
{ 
    <.IntegerPart> <.FractionalPart> |
    <.IntegerPart> <.ExponentPart>   |
    <.IntegerPart> <.FractionalPart> <.ExponentPart>
}

token FractionalPart { '.' <.Digit>+ }

token ExponentPart { <.ExponentIndicator> <.Sign>? <.Digit>+ }

token ExponentIndicator { [ 'e' | 'E' ] }

token Sign { [ '+' | '-' ] }

# copied string stuff from JSON::Tiny

token StringValue { '"' ~ '"' [ <str> | \\ <str=.str_escape> ]* }

token str { <-["\\\t\r\n]>+ }

token str_escape { <["\\/bfnrt]> | 'u' <utf16_codepoint>+ % '\u' }

token utf16_codepoint { <.xdigit>**4 }

# Query Document

token ws { <.Ignored>* }

rule Document { <.ws> <.Comment>* % <.ws> <Definition>+ }

rule Definition { <.Comment>* % <.ws> 
                      [ <OperationDefinition> | <FragmentDefinition> ] }

rule OperationDefinition
{
    <SelectionSet> |
    <OperationType> <Name>? <VariableDefinitions>? <Directives>? <SelectionSet>
}

token OperationType { 'query' | 'mutation' }

rule SelectionSet { '{' [ <.Comment>* % <.ws>
                        <Selection>+
                        <.Comment>* % <.ws>
                    '}' || <expect('}')> ] }

rule Selection { <QueryField> | <FragmentSpread> | <InlineFragment> }

rule QueryField { <Alias>? <Name> <Arguments>? <Directives>? <SelectionSet>? }

rule Alias { <Name> ':' }

rule Arguments { '(' <Argument>+ ')' }

rule Argument { <Name> ':' <Value> }

rule FragmentSpread { '...' <FragmentName> <Directives>? }

rule InlineFragment { '...' <TypeCondition>? <Directives>? <SelectionSet> }

rule FragmentDefinition
{
    'fragment' <FragmentName> <TypeCondition> <Directives>? <SelectionSet>
}

rule FragmentName { <Name><!after ' on'> }

rule TypeCondition { 'on' <NamedType> }

proto token Value {*};
      token Value:sym<Variable>     { <Variable>           }
      token Value:sym<FloatValue>   { <FloatValue>         }
      token Value:sym<IntValue>     { <IntValue>           }
      token Value:sym<StringValue>  { <StringValue>        }
      token Value:sym<BooleanValue> { [ 'true' | 'false' ] }
      token Value:sym<NullValue>    { 'null'               }
      token Value:sym<EnumValue>    { <Name>               }
      token Value:sym<ListValue>    { <ListValue>          }
      token Value:sym<ObjectValue>  { <ObjectValue>        }

rule ListValue { '[' <Value>* % <.ws> ']' }

rule ObjectValue { '{' <ObjectField>* % <.ws> '}' }

rule ObjectField { <Name> ':' <Value> }

rule VariableDefinitions { '(' <VariableDefinition>+ % <.ws> ')' }

rule VariableDefinition { <Variable> ':' <Type> <DefaultValue>? }

rule Variable { '$' <Name> }

rule DefaultValue { '=' <Value> }

rule Type { <NonNullType> | <NamedType> | <ListType> }

rule NamedType { <Name> }

rule ListType { '[' <Type> ']' }

rule NonNullType { <NamedType> '!' | <ListType> '!' }

rule Directives { <Directive>+ % <.ws> }

rule Directive { '@' <Name> <Arguments>? }

# Type Schema Language
# Mostly cribbed from 
# https://wehavefaces.net/graphql-shorthand-notation-cheatsheet-17cd715861b6

rule TypeSchema { <.ws> <TypeDefinition>+ }

rule TypeDefinition { <Interface>   |
                      <Scalar>      |
                      <ObjectType>  |
                      <Union>       |
                      <Enum>        |
                      <InputObject> |
                      <Schema> }

rule Interface
{ <Comment>* % <.ws> 'interface' <Name> <FieldList> }

rule FieldList { '{' <Field>+ '}' }

rule Field
{ <Comment>* % <.ws> <Name> <ArgumentDefinitions>? ':' <Type> <Directives>? }

rule ArgumentDefinitions { '(' <ArgumentDefinition>+ % <.ws> ')' }

rule ArgumentDefinition { <Name> ':' <Type> <DefaultValue>? }

rule Scalar
{ <Comment>* % <.ws> 'scalar' <Name> }

rule ObjectType
{ <Comment>* % <.ws> 'type' <Name> <Implements>?
                            <FieldList> }

rule Implements { 'implements' <Name>+ % <.ws> }

rule Union
{ <Comment>* % <.ws> 'union' <Name> '=' <UnionList> }

rule UnionList { <Name>+ % <.UnionSep> }

rule UnionSep { <.ws> '|'  }

rule Enum
{ <Comment>* % <.ws> 'enum' <Name> '{' <EnumValues> '}' }

rule EnumValues { <EnumValue>+ }

rule EnumValue { <Comment>* % <.ws> <Name> <Directives>? }

rule InputObject
{ <Comment>* % <.ws> 'input' <Name> <InputFieldList> }

rule InputFieldList { '{' <InputField>+ '}' }

rule InputField
{ <Comment>* % <.ws> <Name> ':' <Type> <DefaultValue>? }

rule Schema { <Comment>* % <.ws> 
                  'schema' '{'
                  <SchemaQuery>?
                  <SchemaMutation>?
                  <SchemaSubscription>?
                  '}' }

rule SchemaQuery { 'query' ':' <Name> }

rule SchemaMutation { 'mutation' ':' <Name> }

rule SchemaSubscription { 'subscription' ':' <Name> }

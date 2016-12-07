#use Grammar::Tracer;

unit grammar GraphQL::Grammar;

token SourceCharacter { <[\x[0009]\x[000A]\x[000D]\x[0020]..\x[FFFF]]> }

token Ignored
{ <UnicodeBOM> | <WhiteSpace> | <LineTerminator> | <Comma> | <Comment> }

token UnicodeBOM { \x[FEFF] }

token WhiteSpace { \x[0009] | \x[0020] }

token LineTerminator
{ [ \x[000A] | \x[000D]<!before \x[000A]> | \x[000D]\x[000A] ]}

token Comment { '#' <CommentChar>* }

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
  [
    <.IntegerPart> <.FractionalPart> |
    <.IntegerPart> <.ExponentPart>   |
    <.IntegerPart> <.FractionalPart> <.ExponentPart>
  ]
}

token FractionalPart { '.' <.Digit>+ }

token ExponentPart { <.ExponentIndicator> <.Sign>? <.Digit>+ }

token ExponentIndicator { [ 'e' | 'E' ] }

token Sign { [ '+' | '-' ] }

token StringValue { '"' <InsideString> '"' }

token InsideString { <.StringCharacter>* }

token StringCharacter
{
   <[\x[0009]\x[000A]\x[000D]\x[0020]..\x[FFFF]]-[\"\\\r\n]> | 
   '\u' <EscapedUnicode> | 
   \\ <EscapedCharacter>
}

token EscapedUnicode { <[0..9A..Fa..f]> ** 4 }

token EscapedCharacter { <[\"\\/bfnrt]> }

# Query Document

token ws { <.Ignored>* }

rule Document { <.ws> <Definition>+ }

rule Definition { <OperationDefinition> | <FragmentDefinition> }

rule OperationDefinition
{
    <SelectionSet> |
    <OperationType> <Name>? <VariableDefinitions>? <Directives>? <SelectionSet>
}

token OperationType { 'query' | 'mutation' }

rule SelectionSet { '{' <Selection>+ '}' }

rule Selection { <Field> | <FragmentSpread> | <InlineFragment> }

rule Field { <Alias>? <Name> <Arguments>? <Directives>? <SelectionSet>? }

rule Alias { <Name> ':' }

rule Arguments { '(' <Argument>+ ')' }

rule Argument { <Name> ':' <Value> }

rule FragmentSpread { '...' <FragmentName> <Directives>? }

rule InlineFragment { '...' <TypeCondition>? <Directives>? <SelectionSet> }

rule FragmentDefinition
{
    'fragment' <FragmentName> <TypeCondition> <Directives>? <SelectionSet>
}

rule FragmentName { <Name><!after 'on'> }

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

rule TypeDefinition { <InterfaceDefinition>  |
                      <ScalarDefinition>     |
                      <ObjectTypeDefinition> |
                      <UnionDefinition>      |
                      <EnumDefinition>       |
                      <InputDefinition>      |
                      <SchemaDefinition> }

rule InterfaceDefinition { 'interface' <Name> <FieldDefinitionList> }

rule FieldDefinitionList { '{' <FieldDefinition>+ '}' }

rule FieldDefinition { <Name> <ArgumentDefinitions>? ':' <Type> }

rule ArgumentDefinitions { '(' <ArgumentDefinition>+ % <.ws> ')' }

rule ArgumentDefinition { <Name> ':' <Type> <DefaultValue>? }

rule ScalarDefinition { 'scalar' <Name> }

rule ObjectTypeDefinition { 'type' <Name> <ImplementsDefinition>?
                            <FieldDefinitionList> }

rule ImplementsDefinition { 'implements' <Name>+ % <.ws> }

rule UnionDefinition { 'union' <Name> '=' <UnionList> }

rule UnionList { <Name>+ % <.UnionSep> }

rule UnionSep { <.ws> '|'  }

rule EnumDefinition { 'enum' <Name> '{' <EnumValues> '}' }

rule EnumValues { <Name>+ % <.ws> }

rule InputDefinition { 'input' <Name> <FieldDefinitionList> }

rule SchemaDefinition { 'schema' '{'
                            <SchemaQuery>?
                            <SchemaMutation>?
                        '}' }

rule SchemaQuery { 'query' ':' <Name> }

rule SchemaMutation { 'mutation' ':' <Name> }

rule SchemaSubscription { 'subscription' ':' <Name> }

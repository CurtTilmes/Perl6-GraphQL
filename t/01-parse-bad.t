use v6;

use Test;
use lib 'lib';

use GraphQL::Grammar;

my @query = 
# 1
'{this',
'expected } at line 1',

;

for @query -> $query, $expected
{
    try
    {
        GraphQL::Grammar.parse($query, rule => 'Document') || die;
        CATCH
        {
            default
            {
                like ~$_, /$expected/, "Caught parse error";
            }
        }
    }
}

done-testing;

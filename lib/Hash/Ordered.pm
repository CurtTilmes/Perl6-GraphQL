unit module Hash::Ordered;

class Hash::Ordered does Associative
{
    has %!hash handles <AT-KEY EXISTS-KEY elems gist perl>;
    has @!keys = ();

    method new(*%args) {
        my $h = self.bless;
        for %args.kv -> $k, $v
        {
            $h.ASSIGN-KEY($k, $v);
        }
        return $h;
    }

    method ASSIGN-KEY($key, $new)
    {
	self.DELETE-KEY($key) if %!hash{$key}:exists;
	push @!keys, $key;
	%!hash.ASSIGN-KEY($key, $new);
    }

    method DELETE-KEY($key)
    {
        return unless %!hash{$key}:exists;
	my $pos = @!keys.first($key, :k) or return;
        @!keys.splice($pos, 1);
	%!hash.DELETE-KEY($key);
    }
    
    method keys { @!keys }

    method values { %!hash{@!keys} }

    method kv { @!keys.map({ slip($_, %!hash{$_}) }) }
}

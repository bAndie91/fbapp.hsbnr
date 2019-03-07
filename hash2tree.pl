
require "/opt/fbapp/hsbnr/indent2tree.pl";

sub hash2indent
{
	my ($subHash, $indent) = @_;
	my $output;
	$indent //= '';
	if(ref $subHash eq '')
	{
		$output .= sprintf "%s%s\n", $indent, $subHash if defined $subHash;
	}
	elsif(ref $subHash eq 'HASH')
	{
		for my $key (sort keys %$subHash)
		{
			$output .= sprintf "%s%s\n", $indent, $key;
			$output .= hash2indent($subHash->{$key}, "$indent\t");
		}
	}
	return $output;
}

sub hash2tree
{
	return indent2tree(hash2indent($_[0]));
}

1;

#!/usr/bin/env perl

sub indent2tree
{

my $spaces_prev = 0;
my $level = 0;
my %level_spaces = (0=>0);
my $Tree = { subtree=>[], };
my $ForkPoint = $Tree;
my $spaces;
my $data;

open my $input, '<', \$_[0];
for(<$input>)
{
	s/^(\s*)//;
	$spaces = length $1;
	s/\r?\n//;
	$data = $_;
	while(/\\$/)
	{
		$data =~ s/\\$/\n/;
		$_ = <$input>;
		s/^\s{$spaces}//;
		s/\r?\n//;
		$data .= $_;
	}
	
	if($spaces > $spaces_prev)
	{
		$level++;
		$level_spaces{$level} = $spaces;
		$ForkPoint = $ForkPoint->{subtree}->[$#{$ForkPoint->{subtree}}];
	}
	elsif($spaces < $spaces_prev)
	{
		while($spaces < $level_spaces{$level})
		{
			$level--;
			$ForkPoint = $ForkPoint->{parent};
		}
	}
	
	push $ForkPoint->{subtree}, {data=>$data, parent=>$ForkPoint, subtree=>[]};
	
	$spaces_prev = $spaces;
}
close $input;

sub print_subtree
{
	my $subtree = shift;
	my $level = shift;
	my $sidebranches = shift;
	my $pos = 0;
	my $output;
	
	for my $node (@$subtree)
	{
		my $last = $pos == $#$subtree;
		
		if($level == 0)
		{
			$output .= sprintf "%s\n", $node->{data};
			
			$output .= print_subtree($node->{subtree}, $level+1, '');
		}
		else
		{
			my $linenumber = 0;
			
			for my $line (split /\n/, $node->{data})
			{
				$output .= sprintf "%s%s %s\n",
					$sidebranches,
					$linenumber == 0
						? ($last ? '└' : '├').'──'
						: ($last ? ' ' : '│').'  ',
					$line;
				$linenumber++;
			}
			
			$output .= print_subtree($node->{subtree}, $level+1, $sidebranches . ($last ? '    ' : '│   '));
		}
		
		$pos++;
	}
	
	return $output;
}

return print_subtree($Tree->{subtree}, 0, '');
}

1;

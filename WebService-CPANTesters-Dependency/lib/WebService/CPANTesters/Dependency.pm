package WebService::CPANTesters::Dependency;

use strict;
use warnings;

our $VERSION = '0.01';

use base qw/Class::Accessor::Fast/;

use Carp qw/croak/;
use List::Rubyish;
use LWP::UserAgent;
use Perl::Version;
use URI::Template::Restrict;
use XML::LibXML::XPathContext;
use Smart::Comments;

__PACKAGE__->mk_accessors(qw/
    perl
    os
    module
    depth
    warning
    text_result
    is_pure_perl
    total_results
    passes
    fails
    unknowns
    nas
    is_core
    dependencies
 /);

our ($PERL_VERSION) = Perl::Version->new($])->normal =~ m/^v(.*)$/;
our $ENDPOINT_TMPL  = URI::Template::Restrict->new(
    q#http://deps.cpantesters.org/?{-join|;|module,perl,os,xml}#
);

sub new {
    my ($class, $args) = @_;

    $args->{dependencies} ||= List::Rubyish->new([]);
    $args->{depth} ||= 0;

    return $class->SUPER::new($args);
}

sub find {
    my ($self, $module, $args) = @_;

    croak(q|Please specifiy module name.|) unless ($module);

    $args ||= +{};
    $args = +{
        perl => $PERL_VERSION,
        os => 'Linux',
        %$args,
        xml => 1,
        module => $module,
    };

    ### $args
    
    my $uri = $ENDPOINT_TMPL->process($args);

    ### $uri
    
    my $ua  = LWP::UserAgent->new;
    my $res = $ua->get($uri);

    return unless ($res->is_success);

    my $parser = XML::LibXML->new;
    my $doc = $parser->parse_string($res->content);
    my $xpc = XML::LibXML::XPathContext->new($doc);

    $self->module($xpc->findvalue(q|//cpandeps/module|));
    $self->perl(Perl::Version->new($xpc->findvalue(q|//cpandeps/perl|)));
    $self->os($xpc->findvalue(q|//cpandeps/os|));

    my @dep_nodes = $xpc->findnodes(q|//cpandeps/dependency|);
    my $dep_self_node = shift @dep_nodes;

    for (my $i = 0; $i < $#dep_nodes; $i++) {
        my $dep_node = $dep_nodes[$i];
        if ($self->parse_dependency($self, \@dep_nodes, \$i)) {
            $i--;
        }
    }

#     for my $dep_node (@dep_nodes) {
#         my $dep_args = +{
#             module => $dep_node->findvalue(q|./module|),
#             depth  => $dep_node->findvalue(q|./depth|),
#             warning => $dep_node->findvalue(q|./warning|),
#             text_result => $dep_node->findvalue(q|./textresult|),
#             is_pure_perl => $dep_node->findvalue(q|./ispureperl|),
#             total_results => $dep_node->findvalue(q|./totalresults|),
#             passes => $dep_node->findvalue(q|./passes|) || undef,
#             fails => $dep_node->findvalue(q|./fails|) || undef,
#             nas => $dep_node->findvalue(q|./nas|) || undef,
#         };

#         $dep_args->{is_core} = (defined $dep_args->{text_result} && $dep_args->{text_result} eq 'Core module') ? 1 : 0;
#         $dep_args->{start_depth} = $self->start_depth + $dep_args->{depth};

#         my $dependency = WebService::CPANTesters::Dependency->new($dep_args);

#         ### $dep_args

#         $self->dependencies->push($dependency);
#     }
    1;
}

sub naritoshi {
    my ($self, $parent, $ret, $deps) = @_;
    $parent ||= $self;
    $ret    ||= [];
    $deps   ||= $parent->dependencies;

    for my $dep (@{$deps->to_a}) {
        ### $dep
        push(@$ret, +{ module =>  $dep->module, depth => $dep->depth });
        $self->naritoshi($dep, $ret, $dep->dependencies);
    }

    return @$ret;
}


sub parse_dependency {
    my ($self, $parent, $dep_nodes, $idx_ref) = @_;

    my $dep_node = $dep_nodes->[$$idx_ref];
    return 0 unless ($dep_node);
    return 0 unless ($dep_node->findvalue(q|./depth|) > $parent->depth);
    
    my $dep_args = +{
        module => $dep_node->findvalue(q|./module|),
        depth  => $dep_node->findvalue(q|./depth|),
        warning => $dep_node->findvalue(q|./warning|),
        text_result => $dep_node->findvalue(q|./textresult|),
        is_pure_perl => $dep_node->findvalue(q|./ispureperl|),
        total_results => $dep_node->findvalue(q|./totalresults|),
        passes => $dep_node->findvalue(q|./passes|) || undef,
        fails => $dep_node->findvalue(q|./fails|) || undef,
        nas => $dep_node->findvalue(q|./nas|) || undef,
    };

    $dep_args->{is_core} = (defined $dep_args->{text_result} && $dep_args->{text_result} eq 'Core module') ? 1 : 0;
    # $dep_args->{start_depth} = $parent->start_depth + $dep_args->{depth};

    my $dependency = WebService::CPANTesters::Dependency->new($dep_args);
    $parent->dependencies->push($dependency);

    ${$idx_ref}++;
    while ($self->parse_dependency($dependency, $dep_nodes, $idx_ref)) {
        ### $idx_ref
    }
    
    return 1;
}


1;
__END__

=head1 NAME

WebService::CPANTesters::Dependency -

=head1 SYNOPSIS

  use WebService::CPANTesters::Dependency;

=head1 DESCRIPTION

WebService::CPANTesters::Dependency is

=head1 AUTHOR

typomaster E<lt>naritoshi.hayashi@gmail.comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

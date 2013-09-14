# ABSTRACT: General Purpose Object Serializer
package Object::Serializer;

use utf8;
use Data::Dumper ();
use Scalar::Util qw(blessed);

our $MARKER = '__CLASS__';
our %TYPES;

our $VERSION = '0.000001'; # VERSION


sub new {
    bless {}, shift
}

sub _hashify {
    my ($self, $object) = @_;
    return unless $object;

    local $Data::Dumper::Terse      = 1;
    local $Data::Dumper::Indent     = 0;
    local $Data::Dumper::Useqq      = 1;
    local $Data::Dumper::Deparse    = 1;
    local $Data::Dumper::Quotekeys  = 0;
    local $Data::Dumper::Sortkeys   = 1;
    local $Data::Dumper::Deepcopy   = 1;
    local $Data::Dumper::Purity     = 0;

    my $subject = Data::Dumper::Dumper($object);

    my $grammar = do {
        use Regexp::Grammars;
        qr{
            bless <.left_paren>
                (?: <.escape> | <.paren_pair> | <.brace_pair> |  <.non_paren> )*
            <.right_paren>
                (?=(?:(?:(?:[^"\\]++|\\.)*+"){2})*+(?:[^"\\]++|\\.)*+$)

            <rule: paren_pair>
                \(  (?: <escape> | <paren_pair> | <brace_pair> | [^()] )*  \)

            <rule: brace_pair>
                \{  (?: <escape> | <paren_pair> | <brace_pair> | [^{}] )*  \}

            <token: escape>       \\ .
            <token: left_paren>   \(
            <token: right_paren>  \)
            <token: non_paren>    [^()]
        }xms;
    };

    while ($subject =~ /$grammar/) {
        my $after = my $before = (values(%/))[0];
        my $class = $1 if $after =~ s/,\s?'([\w:]+)'\s?\)$//;
        my $head  = "'$MARKER' => '$class',";

        $after   =~ s/^bless\(\s?{/{$head/;
        $after   = $after;
        $before  = quotemeta $before;
        $subject =~ s/$before/$after/g;
    }

    return eval qq{ my \$VAR1 = $subject; };
}

sub _typify {
    my ($self, $how, $data) = @_;
    return unless defined $data;

    my $object = $data;

    if ('HASH' eq ref $object) {
        if (exists $object->{$MARKER}) {
            my $class = $object->{$MARKER};
            my $props = {map {$_ => $object->{$_}}
                grep {$_ ne $MARKER} keys %{$object}};

            $object = bless $props, $class;
        }
    }

    my $reftype = ref $object;
    return $data unless defined $reftype and blessed $object;

    my $direction;

    # explicit type
    for my $class (ref $self, __PACKAGE__) {
        my $type = $TYPES{$class};
        next unless 'HASH' eq ref $type;

        my $target = $type->{$reftype};
        next unless 'HASH' eq ref $target;

        $direction = $target->{$how};
        undef $direction unless 'CODE' eq ref $direction;
    }

    # implicit type
    unless ($direction) {
        # todo ... maybe? not yet supported e.g. obj->isa(type)
    }

    delete $data->{$MARKER} if $how eq 'expand';
    return $how eq 'expand' ? $object : $data unless defined $direction;
    return $direction->($object);
}

sub _perform_serialization {
    my ($self, $object) = @_;
    return unless $object;

    my $data;

    if ('ARRAY' eq ref $object) {
        $data = [];
        for my $val (@{$object}) {
            push @{$data} => $self->_perform_serialization($val);
        }
    }
    elsif ('HASH' eq ref $object) {
        $data = {};
        while (my($key, $val) = each(%{$object})) {
            if ('HASH' eq ref $val) {
                $data->{$key} = $self->_perform_serialization($val);
            }
            else {
                $data->{$key} = $val;
            }
        }
        if (exists $data->{$MARKER}) {
            $data = $self->_typify('collapse', $data);
        }
    }
    else {
        $data = $self->_typify('collapse', $object);
    }

    return $data;
}


sub serialize {
    my ($self, $object) = @_;
    return unless $object // $self;
    return $self->_perform_serialization($self->_hashify($object // $self));
}

sub _perform_deserialization {
    my ($self, $object) = @_;
    return unless $object;

    my $data;

    if ('ARRAY' eq ref $object) {
        $data = [];
        for my $val (@{$object}) {
            push @{$data} => $self->_perform_deserialization($val);
        }
    }
    elsif ('HASH' eq ref $object) {
        $data = {};
        while (my($key, $val) = each(%{$object})) {
            if ('HASH' eq ref $val) {
                $data->{$key} = $self->_perform_deserialization($val);
            }
            else {
                $data->{$key} = $val;
            }
        }
        if (exists $data->{$MARKER}) {
            $data = $self->_typify('expand', $data);
        }
    }
    else {
        $data = $self->_typify('expand', $object);
    }

    return $data;
}


sub deserialize {
    my ($self, $object) = @_;
    return unless $object;
    return $self->_perform_deserialization($self->_hashify($object));
}


sub serialize::object {
    my ($namespace, $reftype, %attributes) = @_;

    die "Couldn't register type serializer due to invalid arguments" unless
        $namespace && $reftype && (
            'CODE' eq ref $attributes{collapse} ||
            'CODE' eq ref $attributes{expand}
        )
    ;

    return $TYPES{ref($namespace) // $namespace}{$reftype} = {%attributes};
}

1;

__END__

=pod

=head1 NAME

Object::Serializer - General Purpose Object Serializer

=head1 VERSION

version 0.000001

=head1 SYNOPSIS

    package Point;

    use Moo;
    use parent 'Object::Serializer';

    has 'x' => (is => 'rw');
    has 'y' => (is => 'rw');

    package main;

    my $p = Point->new(x => 10, y => 10);

    # serialize the class into a hash
    my $p1 = $p->serialize; # returns { __CLASS__ => 'Point', x => 10, y => 10 }

    # deserialize the hash into a class
    my $p2 = $p->deserialize($p1);

=head1 DESCRIPTION

Formatting data structures into an ideal format for passing representations in
and out of applications can be a real pain. Object::Serializer is a fast and
simple pure-perl framework-agnostic type-less none-opinionated light-weight
primative general purpose object serializer. While module should be considered
experimental, I don't anticipate the interface changing, much.

=head1 METHODS

=head2 serialize

The serialize method expects an object and returns a serialized (hashified)
version of that object.

    my $hash = $self->serialize($object);

=head2 deserialize

The deserialize method expects an object, preferrably a pre-serialized one, and
returns a deserialized version of that object.

    my $object = $self->deserialize($object);

=head2 serialize::object

The serialize::object method expects a reftype and a list of key/value pairs
having the keys expand and/or collapse. This method registers a custom
serializer to be used during the expansion and/or collapsing occurrences.

    CLASS->serialize::object(
        TYPE => (
            expand   => sub { ... },
            collapse => sub { ... }
        )
    );

=head1 EXTENSION

Object::Serializer can be used as a serializer independently, however, it is
primarily designed to be used as a base class for your own classes or roles. By
default, Object::Serializer doesn't do anything special for you in the way of
serialization, however, you can easily hook into the serialization process by
defining your own custom serialization routines. The following sytax is what you
might use to register your own custom serializers:

    Object::Serializer->serialize::object(
        DateTime => ( collapse => sub { pop->iso8601 } )
    );

This method call registers a custom serializer that is executed globally
whenever a DateTime object if found. The expand and collapse coderefs suggest
what will happen on deserialization and serialization respectively,
additionally, you can register custom serializers to only be used when invoked
by a specific class. The following sytax is what you might use to register a
custom serializer with a specific class:

    Point->serialize::object(
        DateTime => ( collapse => sub { pop->iso8601 } )
    );

=head1 CAVEATS

Circular references are specifically disallowed, however if you can break the
cycles yourself then re-assemble them later you can get around this. Custom
serializers must match the object's reftype exactly to be enacted. Extending the
serialization process with custom serializers usually means losing the ability
to recreate the serialized objects.

=head1 AUTHOR

Al Newkirk <anewkirk@ana.io>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Al Newkirk.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

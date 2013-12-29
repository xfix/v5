#!perl6

my $have_parrot = 1;

# That goes into the Makefile.
my %config =
    p_perl6           => "PERL6LIB={cwd}/lib perl6-p",
    p_modules         => '',
    p_modules_list    => '',
    p_modules_install => "\t\$(MKPATH) \$(P_P6LIB)/lib/Perl5\n\t\$(CP) lib/Perl5/Terms.pbc \$(P_P6LIB)/lib/Perl5/\n",
;
my regex name { [\w+]+ % '::' };
my regex desc { <-[\n\[]>+ };
my regex deps { '[' <name>+ % ' ' ']' { make $<name>.list>>.Str } };

my %p_module_paths;
my @modules = "build/core_modules".IO.slurp.lines.grep(/^\w/).map({
    /^ <name> ' - ' <desc> <deps>?/;
    { :name(~$<name>), :desc(~$<desc>), :deps($<deps> ?? $<deps>.ast !! []) }
});

my $i = 0;
my $l = 0;
for @modules -> $module {
    my @name_parts         = $module<name>.split('::');
    my $basename           = @name_parts.join('/');
    my $pm                 = "lib/Perl5/$basename.pm";
    my $last               = $i == @modules.end;
    $l                    += $pm.chars + 2;
    my $break_modules_list = !$last && $l > 110;
    $l                     = 0 if $break_modules_list;

    if $have_parrot {
        my $pbc                  = "lib/Perl5/$basename.pbc";
        my $pir                  = "lib/Perl5/$basename.pir";
        %config<p_modules_list> ~= "$pbc ";
        %config<p_modules_list> ~= "\\\n\t" if $break_modules_list;
        my $deps                 = join ' ', $module<deps>>>.map({ 'lib/Perl5/' ~ .split('::').join('/') ~ '.pir' });

        %config<p_modules> ~= qq:to/P_MODULES/.subst('    ', "\t", :g);
            $pir: $pm $deps
            \t@echo Compiling $module<name> to pir
            \t@\$(P_PERL6) --target=pir --output=$pir $pm
            $pbc: $pir
            \t@echo Compiling $module<name> to pbc
            \t@\$(P_PARROT) -o $pbc $pir
            
            P_MODULES

        for 0..^@name_parts.end {
            my $path = @name_parts[0..$_].join('/');
            unless %p_module_paths{ $path } {
                %config<p_modules_install> ~= "\t\$(MKPATH) \$(P_P6LIB)/lib/Perl5/$path\n";
                %p_module_paths{ $path }    = 1;
            }
        }

        %config<p_modules_install> ~= "\t\$(CP) $pbc \$(P_P6LIB)/lib/Perl5/" ~ @name_parts[0..^@name_parts.end].join('/') ~ "\n"
    }

    $i++;
}

my $Makefile = fill_template 'build/Makefile-common.in';
$Makefile   ~= fill_template 'build/Makefile-Parrot.in' if $have_parrot;

"Makefile".io.spurt: $Makefile;

sub fill_template($file, :%values = %config) {
    my $template = $file.IO.slurp;
    $template .= subst(/ '@' (\w+) '@' /, { %values{$0} // note "unknown key '$0' in '$file'" }, :g)
}


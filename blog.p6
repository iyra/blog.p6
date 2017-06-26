# blog.p6, authored by iyra
# Copyright (C) 2017 iyra
# license: CC0 1.0 Universal Public Domain Dedication
# https://creativecommons.org/publicdomain/zero/1.0/

use SCGI;
use Digest::SHA;

my %langs = { 'en' => 'English', 'ja' => 'Japanese' };
my $pass = "replace this with a sha256'd password";
my $blog-title = "my blog";

sub buf_to_hex { [~] $^buf.list».fmt: "%02x" }

sub make-page($title, $c) {
	my @out;
	@out.push: '<!doctype html><head><meta charset="utf-8"><title>';
	@out.push: $title;
	@out.push: '</title><link rel="stylesheet" type="text/css" href="/s.css"></head><body>';
	@out.push: "<div id='main'><h1>{$blog-title}</h1>";
	@out.push: $c;
	@out.push: "</div>";
	@out.push: "<div id='links'><a class='pbm' href='/'>Home</a> - <a class='pbm' href='/blog'>Blog</a> - <a class='pbm' href='/blog?months'>Entries by month</a></div>";
	@out.push: "<footer><a title='kopimi: feel free to copy anything here and do whatever you want with it.' href='http://www.kopimi.com/'><img src='/kopimi.gif' width=100></a></footer>";
	@out.push: "</body></html>";
	return @out.join("");
}

sub make-post(Int $id, Str $title, Str $lang, Str $text, DateTime $date, @langs) {
	my @ht-langs;
	for @langs -> $mlang {
		@ht-langs.push: sprintf('<a href=/blog?view&id=%d&lang=%s>%s</a>', $id, $mlang, %langs{$mlang});
	}
	my $ls = @ht-langs.join(", ");
	my @out;
	my $ds = $date.Str;
	@out.push: "<div class='post-box'><div class='post-title'>{$ds}, {$lang} :: (<span class='langlist'>{$ls}</span>) <a class='title' href='/blog?view&id={$id}&lang={$lang}'>{$title}</a></div><div class='post-text'>{$text}</div></div>";
	return @out.join("");
} 

sub post-properties($p) {
	say("opening ", $p);
	my %properties;
	my $tag = '';
	my $bf = sub ($self) { sprintf "%02d-%02d-%04d %02d:%02d", .day, .month, .year, .hour, .minute given $self; };
	for $p.lines -> $line {
		if $line ~~  m/^':'(\w+)' '(.+)$/ {
			$tag = $0.Str;
			##say $line;
			if $0.Str ne 'DATE' {
				%properties{$0.Str} = $1.Str;
			} else {
				%properties{'DATE'} = DateTime.new($1.Str, formatter=> $bf).DateTime;
			}
		} else {
			if $tag ne '' {
				%properties{$tag} = sprintf("%s\n%s", %properties{$tag}, $line);
			} else {
				say("Error parsing, tagless line outside of tag scope.");
			}
		}
	}
	return %properties;
}

sub post-exists(Str $dir, Int $id, Str $lang) {
	return "{$dir}/{$id}/{$lang}.dat".IO.e;
}

sub load-post(Str $dir, Int $id, Str $lang) {
	my %x = post-properties("{$dir}/{$id}/{$lang}.dat".IO);
	dd %x;
	return %x;
}

sub load-posts(Str $dir) {
	my %posts;
	my @post-dirs = grep { $_.d }, $dir.IO.dir(test => /^\d+$/);
	for @post-dirs -> $post-dir {
		my @post-files = $post-dir.IO.dir(test=>/\.dat$/);
		my %posts-properties;
		for @post-files -> $post-file {
			my %properties = post-properties($post-file);
			if split('/', $post-file.Str).tail ~~ m/^(\w\w)\.dat$/ {
				%posts-properties{$0} = %properties;
			}
			## %posts-properties{$post-file} = %properties;
		}
		%posts{split('/', $post-dir.Str).tail.Int} = %posts-properties;
	}
	dd %posts.sort({$^b.key cmp $^a.key});
	return %posts;
}

sub month-posts(Str $dir, Int $year, Int $month) {
	my %p;
	my %posts = load-posts($dir);
	for %posts.keys -> $k {
		for %posts{$k}.keys -> $f-k {
			my $date = %posts{$k}{$f-k}<DATE>;
			if $date.year == $year && $date.month == $month {
				%p{$k} = %posts{$k};
			}
		}
	}
	return %p;
}

sub post-months(Str $dir) {
	my @m;
	my %posts = load-posts($dir);
        for %posts.keys -> $k {
                for %posts{$k}.keys -> $f-k {
                        my $date = %posts{$k}{$f-k}<DATE>;
			if !@m.grep(*.<year> == $date.year && *.<month> == $date.month) {
				say "doesn't already exist, pushing";
				@m.push: {year => $date.year, month => $date.month};
			}
		}
	}
	return @m;
}

sub new-post(Str $dir, Str $lang, Str $title, Str $text, Int $year, Int $month, Int $day, Int $hour, Int $min, Int $sec, $id=-1){
        my @post-dirs=grep {$_.d}, $dir.IO.dir(text => /^\d+$/);
        my $post-id;
        if $id > -1 {
                $post-id = $id;
        } else {
                my $max = -1;
                for @post-dirs -> $post-dir {
                        my $num = split('/', $post-dir.Str).tail.Int;
                        if $num > $max {
                                $max = $num;
                        }
                }
                $post-id = $max+1;
        }
        mkdir("$dir/$post-id");
        my @p;
        my $monthf = sprintf '%02d', $month;
        my $dayf = sprintf '%02d', $day;
        my $hourf = sprintf '%02d', $hour;
        my $minf = sprintf '%02d', $min;
        my $secf = sprintf '%02d', $sec;
        @p.push: ":TITLE $title";
        @p.push: ":DATE {$year}-{$monthf}-{$dayf}T{$hourf}:{$minf}:{$secf}";
        @p.push: ":TEXT $text";
        spurt "$dir/$post-id/$lang.dat", join("\n",@p);
	return $post-id;
}


sub unescape($string is copy) {
	say $string;
        $string .= subst('+', ' ', :g);
        # RAKUDO: This could also be rewritten as a single .subst :g call.
        #         ...when the semantics of .subst is revised to change $/,
        #         that is.
        # The percent_hack can be removed once the bug is fixed and :g is
        # added
        while $string ~~ / ( [ '%' <[0..9A..F]>**2 ]+ ) / {
            $string .= subst( ~$0,
            percent-hack-start( decode-urlencoded-utf8( ~$0 ) ) );
        }
        return percent-hack-end( $string );
}

sub percent-hack-start($str is copy) {
        if $str ~~ '%' {
            $str = '___PERCENT_HACK___';
        }
        return $str;
}

sub percent-hack-end($str) {
       return $str.subst('___PERCENT_HACK___', '%', :g);
}

sub decode-urlencoded-utf8($str) {
        my $r = '';
        my @chars = map { :16($_) }, $str.split('%').grep({$^w});
        while @chars {
            my $bytes = 1;
            my $mask  = 0xFF;
            given @chars[0] {
                when { $^c +& 0xF0 == 0xF0 } { $bytes = 4; $mask = 0x07 }
                when { $^c +& 0xE0 == 0xE0 } { $bytes = 3; $mask = 0x0F }
                when { $^c +& 0xC0 == 0xC0 } { $bytes = 2; $mask = 0x1F }
            }
            my @shift = (^$bytes).reverse.map({6 * $_});
            my @mask  = $mask, Slip(0x3F xx $bytes-1);
            $r ~= chr( [+] @chars.splice(0,$bytes) »+&« @mask »+<« @shift );
        }
        return $r;
}

sub add-param(Str $key, $value, %params){
        #`(if %params{$key} :exists {
            # RAKUDO: ~~ Scalar
            if %params{$key} ~~ Str | Int {
                my $old_param = %params{$key};
                %params{$key} = [ $old_param, $value ];
            }
            elsif %params{$key} ~~ Array {
                %params{$key}.push( $value );
            }
        }
        else {
            %params{$key} = $value;
        })
	
	# just overwrite new parameters
	%params{$key} = $value;
}


#`(
sub parse-params($string, %params, @keywords) {
        if $string ~~ / '&' | ';' | '=' / {
            my @param_values = $string.split(/ '&' | ';' /);

            for @param_values -> $param_value {
                my @kvs = $param_value.split("=");
                add-param( @kvs[0], unescape(@kvs[1]), %params);
            }
        }
        else {
            parse-keywords($string, @keywords);
        }
} )

sub parse-params($string, %params, @keywords) {
	my @param_kvs = $string.split(/ '&' | ';' /);
	my @this-k;
	for @param_kvs -> $param_kv {
		my @kv = $param_kv.split("=");
		if @kv.elems == 1 { @keywords.push: @kv[0]; }
		else {
			add-param(@kv[0], unescape(@kv[1]), %params);	
		}
	}
}

sub parse-keywords (Str $string is copy, @keywords) {
        my $kws = unescape($string);
        @keywords = $kws.split(/ \s+ /);
}

my $scgi = SCGI.new( :port(8118) );

my $handler = sub (%env) 
{
	my %params;
	my @keywords;
	my @body;
	my $method = %env<REQUEST_METHOD> // '';
	@body.push: "<!doctype html><head><meta charset='utf-8'></head><body>";
	parse-params(%env<QUERY_STRING> // '', %params, @keywords);
	
	if (%env<REQUEST_METHOD> // '') eq 'POST' {
		my $input;
		parse-params(%env<scgi.request>.input.decode, %params, @keywords);
	}

	dd @keywords;
	@keywords = grep { .Str.chars > 0 }, @keywords;

        my @headers = 'Content-Type' => 'text/html; charset=utf-8';
	my $e;
	if ('post' eq any(@keywords)) || ('edit' eq any(@keywords)) {
		dd %env;
		my $edit = 0;
		my $edit-id = 0;

		if 'edit' eq any(@keywords) {
                                if !%params<id>.Bool { $e = "ERROR: Cannot edit a post without an id parameter."; @headers.push: 'Content-Length' => $e.join.encode.bytes;  return [400, \@headers, $e]; }
                                if %params<id>.Int ~~ Nil { $e = "ERROR: Cannot convert id into an integer."; @headers.push: 'Content-Length' => $e.join.encode.bytes;  return [400, \@headers, $e]; }
                                $edit = 1;
                                $edit-id = %params<id>.Int;
                }

		if ($method eq 'POST') && (all %params<title text lang year month day hour min sec pass>:exists) {
			if buf_to_hex(sha256(%params<pass>)) ne $pass {
				$e = "ERROR: incorrect password";
				@headers.push: 'Content-Length' => $e.join.encode.bytes;
                                return [400, \@headers, $e];
			}
			my $title = %params<title>;
			my $text = %params<text>.trans(
    [ '&amp;',     '&lt;',    '&gt;'    ] =>
    [ '&', '<', '>' ]
);
			my $lang = %params<lang>;
			my $year = %params<year>;
			my $month = %params<month>;
			my $day = %params<day>;
			my $hour = %params<hour>;
			my $min = %params<min>;
			my $sec = %params<sec>;
			dd %params;
			if (($year, $month, $day, $hour, $min, $sec).any.Int ~~ Nil) {
				return [400, \@headers, "ERROR: couldn't convert your date to integer segments."];
			}

			$year = $year.Int;
			$month = $month.Int;
			$day = $day.Int;
			$hour = $hour.Int;
			$min = $min.Int;
			$sec = $sec.Int;

			if !%langs{$lang}.Bool {
				$e =  "ERROR: language not recognised.";
				@headers.push: 'Content-Length' => $e.join.encode.bytes;	
				return [400, \@headers, $e];
			}

			if $year <= 0 {
				$e = "ERROR: invalid year.";
				@headers.push: 'Content-Length' => $e.join.encode.bytes;
                                return [400, \@headers, $e];
			}

			if $month <= 0 || $month > 12 {
				$e = "ERROR: invalid month.";
				@headers.push: 'Content-Length' => $e.join.encode.bytes;
				return [400, \@headers, $e];
			}

			dd $month;
			if $day <= 0 || $day > DateTime.new(year => $year, month => $month).days-in-month {
				$e =  "ERROR: the day $day does not exist in {$year}/$month.";
				@headers.push: 'Content-Length' => $e.join.encode.bytes;
				return [400, \@headers, $e];
			}

			if $sec <= 0 || $sec > 59 || $min <= 0 || $min > 59 || $hour <= 0 || $hour > 24 {
				$e = "ERROR: your minutes, hours or seconds are out of range.";
				@headers.push: 'Content-Length' => $e.join.encode.bytes;
				return [400, \@headers, $e];
			}
		
			my $new-post-id;	
			if !$edit {
				$new-post-id = new-post("post", $lang, $title, $text, $year, $month, $day, $hour, $min, $sec);
			} else {
				$new-post-id = new-post("post", $lang, $title, $text, $year, $month, $day, $hour, $min, $sec, $edit-id);
			}
			@body.push: sprintf('new post id: %d', $new-post-id);
		} else {
			my $plist = %params.fmt('%s: %s', "\n");
			@body.push: $plist;
			@body.push: "Empty submission?";
		}		
		if !$edit {
	 		@body.push: "<h2>New post</h2><form action='/blog?post' method='post'>title <input type='text' name='title'><br>text <textarea name='text'></textarea><br>year <input type='number' name='year'> month <input type='number' name='month'> day <input type='number' name='day'> hour <input type='number' name='hour'> minute <input type='number' name='min'> second <input type='number' name='sec'><br>language <input type='text' name='lang'><br><input type='password' name='pass'> <input type='submit' value='post'>";
		} else {
                        my $lang;
                        if %params<lang>:exists {
                                $lang = %params<lang>;
                                if !%langs{$lang}.Bool {
                                        $e =  "ERROR: language not recognised.";
                                        @headers.push: 'Content-Length' => $e.join.encode.bytes;
                                        return [400, \@headers, $e];
                                }
                        } else {
                                $lang = "en";
                        }

			my $title;
			my $text;
			my $year;
			my $month;
			my $day;
			my $hour;
			my $min;
			my $sec;

                        if post-exists("post", $edit-id.Int, $lang) {
                                my %p = load-post("post", $edit-id.Int, $lang);
				$title = %p<TITLE>;
				$text = %p<TEXT>.trans(
    [ '&',     '<',    '>'    ] =>
    [ '&amp;', '&lt;', '&gt;' ]
);
				$year = %p<DATE>.year;
				$month = %p<DATE>.month;
				$day = %p<DATE>.day;
				$hour = %p<DATE>.hour;
				$min = %p<DATE>.minute;
				$sec = %p<DATE>.second;
                        }
			my $l = %langs{$lang};
			@body.push: "<h2>Edit post ({$edit-id}, {$l})</h2><form action='/blog?edit&id={$edit-id}&lang={$lang}' method='post'>title <input type='text' name='title' value='{$title}'><br>text <textarea name='text'>{$text}</textarea><br>year <input type='number' name='year' value='{$year}'> month <input type='number' name='month' value='{$month}'> day <input type='number' name='day' value='{$day}'> hour <input type='number' name='hour' value='{$hour}'> minute <input type='number' name='min' value='{$min}'> second <input type='number' name='sec' value='{$sec}'><br><input type='password' name='pass'><input type='submit' value='post'>";
		}
	} elsif 'view' eq any(@keywords) {
		if %params<id>:exists {
			my $post-id = %params<id>;

			if $post-id.Int ~~ Nil {
				$e = "ERROR: could not recognise that post id";
				@headers.push: 'Content-Length' => $e.join.encode.bytes;
                                return [400, \@headers, $e];
			}

			my $lang;
			if %params<lang>:exists {
				$lang = %params<lang>;
				if !%langs{$lang}.Bool {
			        	$e =  "ERROR: language not recognised.";
                                	@headers.push: 'Content-Length' => $e.join.encode.bytes;
                                	return [400, \@headers, $e];
				}
			} else {
				$lang = "en";
			}
			my %all-posts = load-posts("post");
			if post-exists("post", $post-id.Int, $lang) {
				my %p = load-post("post", $post-id.Int, $lang);
				## @body.push: sprintf('<h2>%s [%s]</h2> <span class="date">%s</span> <p>%s</p>', %p<TITLE>, $lang, %p<DATE>, %p<TEXT>);

				## sub make-post(Int $id, Str $title, Str $lang, Str $text, DateTime $date)
				@body.push: make-page(%p<TITLE>, make-post($post-id.Int, %p<TITLE>, $lang, %p<TEXT>, %p<DATE>, %all-posts{$post-id}.keys));
			} else {
				$e = sprintf("ERROR: the post with id %d and language %s does not exist.", $post-id.Int, $lang);
				@headers.push: 'Content-Length' => $e.join.encode.bytes;
                                return [404, \@headers, $e];
			}
		}
	} elsif 'month' eq any(@keywords) {
		if all %params<m y>:exists {
			my $month-num = %params<m>;
			my $year-num = %params<y>;
			if ($month-num, $year-num).all.Int ~~ Nil {
                                $e = "ERROR: could not convert the provided month to an integer.";
                                @headers.push: 'Content-Length' => $e.join.encode.bytes;
                                return [400, \@headers, $e];
                        }
			my %posts = month-posts("post", $year-num.Int, $month-num.Int);
			my $l;
			my @posts;
                for %posts.keys -> $pk {
                        if grep "en", %posts{$pk}.keys {
                                $l = "en";
                        } else {
                                for %posts{$pk}.keys -> $post-lang {
                                        if grep $post-lang, %langs.keys {
                                                $l = $post-lang;
                                        }
                                }
                        }
                        @posts.push: make-post($pk.Int, %posts{$pk}{$l}<TITLE>, $l,  %posts{$pk}{$l}<TEXT>, %posts{$pk}{$l}<DATE>, %posts{$pk}.keys);
                }
                @body.push: make-page($blog-title, @posts.join("\n"));
		} else {
			$e = "ERROR: year and month parameters must be supplied.";
			 @headers.push: 'Content-Length' => $e.join.encode.bytes;
                                return [400, \@headers, $e];
		}
	} elsif 'months' eq any(@keywords) {
		my @months = post-months("post");
		dd @months;
		@body.append: "<div id=\"monthlist\"><ul>";
		for @months -> $month {
			dd $month;
			@body.append: sprintf('<li><a class="pbm" href="/blog?month&y=%d&m=%d">%d/%d</a></li>', $month<year>, $month<month>, $month<year>, $month<month>);

		}
		@body.append: "</ul></div>";
		@body = make-page("browse months", @body.join(""));
	} elsif !@keywords.Bool {
		my %posts = load-posts("post").sort({$^b.key cmp $^a.key});
		my @posts;
		my $l;
		for %posts.keys -> $pk {
			if grep "en", %posts{$pk}.keys {
				$l = "en";
			} else {
				for %posts{$pk}.keys -> $post-lang {
					if grep $post-lang, %langs.keys {
						$l = $post-lang;
					}
				}
			}
			@posts.push: make-post($pk.Int, %posts{$pk}{$l}<TITLE>, $l,  %posts{$pk}{$l}<TEXT>, %posts{$pk}{$l}<DATE>, %posts{$pk}.keys);
		}
		@body.push: make-page($blog-title, @posts.join("\n"));
	} else {
	    $e = "ERROR: not found.";
	    @headers.push: 'Content-Length' => $e.join.encode.bytes;
            return [404, @headers, $e];
	}
	
	my $status = '200';
	@headers.push: 'Content-Length' => @body.join.encode.bytes;
	return [ $status, \@headers, \@body ];
}

$scgi.handle: $handler;

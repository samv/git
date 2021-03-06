# git-gui diff viewer
# Copyright (C) 2006, 2007 Shawn Pearce

proc clear_diff {} {
	global ui_diff current_diff_path current_diff_header
	global ui_index ui_workdir

	$ui_diff conf -state normal
	$ui_diff delete 0.0 end
	$ui_diff conf -state disabled

	set current_diff_path {}
	set current_diff_header {}

	$ui_index tag remove in_diff 0.0 end
	$ui_workdir tag remove in_diff 0.0 end
}

proc reshow_diff {{after {}}} {
	global file_states file_lists
	global current_diff_path current_diff_side
	global ui_diff

	set p $current_diff_path
	if {$p eq {}} {
		# No diff is being shown.
	} elseif {$current_diff_side eq {}} {
		clear_diff
	} elseif {[catch {set s $file_states($p)}]
		|| [lsearch -sorted -exact $file_lists($current_diff_side) $p] == -1} {

		if {[find_next_diff $current_diff_side $p {} {[^O]}]} {
			next_diff $after
		} else {
			clear_diff
		}
	} else {
		set save_pos [lindex [$ui_diff yview] 0]
		show_diff $p $current_diff_side {} $save_pos $after
	}
}

proc force_diff_encoding {enc} {
	global current_diff_path
	
	if {$current_diff_path ne {}} {
		force_path_encoding $current_diff_path $enc
		reshow_diff
	}
}

proc handle_empty_diff {} {
	global current_diff_path file_states file_lists
	global diff_empty_count

	set path $current_diff_path
	set s $file_states($path)
	if {[lindex $s 0] ne {_M}} return

	# Prevent infinite rescan loops
	incr diff_empty_count
	if {$diff_empty_count > 1} return

	info_popup [mc "No differences detected.

%s has no changes.

The modification date of this file was updated by another application, but the content within the file was not changed.

A rescan will be automatically started to find other files which may have the same state." [short_path $path]]

	clear_diff
	display_file $path __
	rescan ui_ready 0
}

proc show_diff {path w {lno {}} {scroll_pos {}} {callback {}}} {
	global file_states file_lists
	global is_3way_diff is_conflict_diff diff_active repo_config
	global ui_diff ui_index ui_workdir
	global current_diff_path current_diff_side current_diff_header
	global current_diff_queue

	if {$diff_active || ![lock_index read]} return

	clear_diff
	if {$lno == {}} {
		set lno [lsearch -sorted -exact $file_lists($w) $path]
		if {$lno >= 0} {
			incr lno
		}
	}
	if {$lno >= 1} {
		$w tag add in_diff $lno.0 [expr {$lno + 1}].0
		$w see $lno.0
	}

	set s $file_states($path)
	set m [lindex $s 0]
	set is_conflict_diff 0
	set current_diff_path $path
	set current_diff_side $w
	set current_diff_queue {}
	ui_status [mc "Loading diff of %s..." [escape_path $path]]

	set cont_info [list $scroll_pos $callback]

	if {[string first {U} $m] >= 0} {
		merge_load_stages $path [list show_unmerged_diff $cont_info]
	} elseif {$m eq {_O}} {
		show_other_diff $path $w $m $cont_info
	} else {
		start_show_diff $cont_info
	}
}

proc show_unmerged_diff {cont_info} {
	global current_diff_path current_diff_side
	global merge_stages ui_diff is_conflict_diff
	global current_diff_queue

	if {$merge_stages(2) eq {}} {
		set is_conflict_diff 1
		lappend current_diff_queue \
			[list [mc "LOCAL: deleted\nREMOTE:\n"] d======= \
			    [list ":1:$current_diff_path" ":3:$current_diff_path"]]
	} elseif {$merge_stages(3) eq {}} {
		set is_conflict_diff 1
		lappend current_diff_queue \
			[list [mc "REMOTE: deleted\nLOCAL:\n"] d======= \
			    [list ":1:$current_diff_path" ":2:$current_diff_path"]]
	} elseif {[lindex $merge_stages(1) 0] eq {120000}
		|| [lindex $merge_stages(2) 0] eq {120000}
		|| [lindex $merge_stages(3) 0] eq {120000}} {
		set is_conflict_diff 1
		lappend current_diff_queue \
			[list [mc "LOCAL:\n"] d======= \
			    [list ":1:$current_diff_path" ":2:$current_diff_path"]]
		lappend current_diff_queue \
			[list [mc "REMOTE:\n"] d======= \
			    [list ":1:$current_diff_path" ":3:$current_diff_path"]]
	} else {
		start_show_diff $cont_info
		return
	}

	advance_diff_queue $cont_info
}

proc advance_diff_queue {cont_info} {
	global current_diff_queue ui_diff

	set item [lindex $current_diff_queue 0]
	set current_diff_queue [lrange $current_diff_queue 1 end]

	$ui_diff conf -state normal
	$ui_diff insert end [lindex $item 0] [lindex $item 1]
	$ui_diff conf -state disabled

	start_show_diff $cont_info [lindex $item 2]
}

proc show_other_diff {path w m cont_info} {
	global file_states file_lists
	global is_3way_diff diff_active repo_config
	global ui_diff ui_index ui_workdir
	global current_diff_path current_diff_side current_diff_header

	# - Git won't give us the diff, there's nothing to compare to!
	#
	if {$m eq {_O}} {
		set max_sz 100000
		set type unknown
		if {[catch {
				set type [file type $path]
				switch -- $type {
				directory {
					set type submodule
					set content {}
					set sz 0
				}
				link {
					set content [file readlink $path]
					set sz [string length $content]
				}
				file {
					set fd [open $path r]
					fconfigure $fd \
						-eofchar {} \
						-encoding [get_path_encoding $path]
					set content [read $fd $max_sz]
					close $fd
					set sz [file size $path]
				}
				default {
					error "'$type' not supported"
				}
				}
			} err ]} {
			set diff_active 0
			unlock_index
			ui_status [mc "Unable to display %s" [escape_path $path]]
			error_popup [strcat [mc "Error loading file:"] "\n\n$err"]
			return
		}
		$ui_diff conf -state normal
		if {$type eq {submodule}} {
			$ui_diff insert end [append \
				"* " \
				[mc "Git Repository (subproject)"] \
				"\n"] d_@
		} elseif {![catch {set type [exec file $path]}]} {
			set n [string length $path]
			if {[string equal -length $n $path $type]} {
				set type [string range $type $n end]
				regsub {^:?\s*} $type {} type
			}
			$ui_diff insert end "* $type\n" d_@
		}
		if {[string first "\0" $content] != -1} {
			$ui_diff insert end \
				[mc "* Binary file (not showing content)."] \
				d_@
		} else {
			if {$sz > $max_sz} {
				$ui_diff insert end [mc \
"* Untracked file is %d bytes.
* Showing only first %d bytes.
" $sz $max_sz] d_@
			}
			$ui_diff insert end $content
			if {$sz > $max_sz} {
				$ui_diff insert end [mc "
* Untracked file clipped here by %s.
* To see the entire file, use an external editor.
" [appname]] d_@
			}
		}
		$ui_diff conf -state disabled
		set diff_active 0
		unlock_index
		set scroll_pos [lindex $cont_info 0]
		if {$scroll_pos ne {}} {
			update
			$ui_diff yview moveto $scroll_pos
		}
		ui_ready
		set callback [lindex $cont_info 1]
		if {$callback ne {}} {
			eval $callback
		}
		return
	}
}

proc start_show_diff {cont_info {add_opts {}}} {
	global file_states file_lists
	global is_3way_diff is_submodule_diff diff_active repo_config
	global ui_diff ui_index ui_workdir
	global current_diff_path current_diff_side current_diff_header

	set path $current_diff_path
	set w $current_diff_side

	set s $file_states($path)
	set m [lindex $s 0]
	set is_3way_diff 0
	set is_submodule_diff 0
	set diff_active 1
	set current_diff_header {}

	set cmd [list]
	if {$w eq $ui_index} {
		lappend cmd diff-index
		lappend cmd --cached
	} elseif {$w eq $ui_workdir} {
		if {[string first {U} $m] >= 0} {
			lappend cmd diff
		} else {
			lappend cmd diff-files
		}
	}

	lappend cmd -p
	lappend cmd --no-color
	if {$repo_config(gui.diffcontext) >= 1} {
		lappend cmd "-U$repo_config(gui.diffcontext)"
	}
	if {$w eq $ui_index} {
		lappend cmd [PARENT]
	}
	if {$add_opts ne {}} {
		eval lappend cmd $add_opts
	} else {
		lappend cmd --
		lappend cmd $path
	}

	if {[string match {160000 *} [lindex $s 2]]
        || [string match {160000 *} [lindex $s 3]]} {
		set is_submodule_diff 1
		if {$w eq $ui_index} {
			set cmd [list submodule summary --cached -- $path]
		} else {
			set cmd [list submodule summary --files -- $path]
		}
	}

	if {[catch {set fd [eval git_read --nice $cmd]} err]} {
		set diff_active 0
		unlock_index
		ui_status [mc "Unable to display %s" [escape_path $path]]
		error_popup [strcat [mc "Error loading diff:"] "\n\n$err"]
		return
	}

	set ::current_diff_inheader 1
	fconfigure $fd \
		-blocking 0 \
		-encoding [get_path_encoding $path] \
		-translation lf
	fileevent $fd readable [list read_diff $fd $cont_info]
}

proc read_diff {fd cont_info} {
	global ui_diff diff_active is_submodule_diff
	global is_3way_diff is_conflict_diff current_diff_header
	global current_diff_queue
	global diff_empty_count

	$ui_diff conf -state normal
	while {[gets $fd line] >= 0} {
		# -- Cleanup uninteresting diff header lines.
		#
		if {$::current_diff_inheader} {
			if {   [string match {diff --git *}      $line]
			    || [string match {diff --cc *}       $line]
			    || [string match {diff --combined *} $line]
			    || [string match {--- *}             $line]
			    || [string match {+++ *}             $line]} {
				append current_diff_header $line "\n"
				continue
			}
		}
		if {[string match {index *} $line]} continue
		if {$line eq {deleted file mode 120000}} {
			set line "deleted symlink"
		}
		set ::current_diff_inheader 0

		# -- Automatically detect if this is a 3 way diff.
		#
		if {[string match {@@@ *} $line]} {set is_3way_diff 1}

		if {[string match {mode *} $line]
			|| [string match {new file *} $line]
			|| [regexp {^(old|new) mode *} $line]
			|| [string match {deleted file *} $line]
			|| [string match {deleted symlink} $line]
			|| [string match {Binary files * and * differ} $line]
			|| $line eq {\ No newline at end of file}
			|| [regexp {^\* Unmerged path } $line]} {
			set tags {}
		} elseif {$is_3way_diff} {
			set op [string range $line 0 1]
			switch -- $op {
			{  } {set tags {}}
			{@@} {set tags d_@}
			{ +} {set tags d_s+}
			{ -} {set tags d_s-}
			{+ } {set tags d_+s}
			{- } {set tags d_-s}
			{--} {set tags d_--}
			{++} {
				if {[regexp {^\+\+([<>]{7} |={7})} $line _g op]} {
					set is_conflict_diff 1
					set line [string replace $line 0 1 {  }]
					set tags d$op
				} else {
					set tags d_++
				}
			}
			default {
				puts "error: Unhandled 3 way diff marker: {$op}"
				set tags {}
			}
			}
		} elseif {$is_submodule_diff} {
			if {$line == ""} continue
			if {[regexp {^\* } $line]} {
				set line [string replace $line 0 1 {Submodule }]
				set tags d_@
			} else {
				set op [string range $line 0 2]
				switch -- $op {
				{  <} {set tags d_-}
				{  >} {set tags d_+}
				{  W} {set tags {}}
				default {
					puts "error: Unhandled submodule diff marker: {$op}"
					set tags {}
				}
				}
			}
		} else {
			set op [string index $line 0]
			switch -- $op {
			{ } {set tags {}}
			{@} {set tags d_@}
			{-} {set tags d_-}
			{+} {
				if {[regexp {^\+([<>]{7} |={7})} $line _g op]} {
					set is_conflict_diff 1
					set tags d$op
				} else {
					set tags d_+
				}
			}
			default {
				puts "error: Unhandled 2 way diff marker: {$op}"
				set tags {}
			}
			}
		}
		$ui_diff insert end $line $tags
		if {[string index $line end] eq "\r"} {
			$ui_diff tag add d_cr {end - 2c}
		}
		$ui_diff insert end "\n" $tags
	}
	$ui_diff conf -state disabled

	if {[eof $fd]} {
		close $fd

		if {$current_diff_queue ne {}} {
			advance_diff_queue $cont_info
			return
		}

		set diff_active 0
		unlock_index
		set scroll_pos [lindex $cont_info 0]
		if {$scroll_pos ne {}} {
			update
			$ui_diff yview moveto $scroll_pos
		}
		ui_ready

		if {[$ui_diff index end] eq {2.0}} {
			handle_empty_diff
		} else {
			set diff_empty_count 0
		}

		set callback [lindex $cont_info 1]
		if {$callback ne {}} {
			eval $callback
		}
	}
}

proc apply_hunk {x y} {
	global current_diff_path current_diff_header current_diff_side
	global ui_diff ui_index file_states

	if {$current_diff_path eq {} || $current_diff_header eq {}} return
	if {![lock_index apply_hunk]} return

	set apply_cmd {apply --cached --whitespace=nowarn}
	set mi [lindex $file_states($current_diff_path) 0]
	if {$current_diff_side eq $ui_index} {
		set failed_msg [mc "Failed to unstage selected hunk."]
		lappend apply_cmd --reverse
		if {[string index $mi 0] ne {M}} {
			unlock_index
			return
		}
	} else {
		set failed_msg [mc "Failed to stage selected hunk."]
		if {[string index $mi 1] ne {M}} {
			unlock_index
			return
		}
	}

	set s_lno [lindex [split [$ui_diff index @$x,$y] .] 0]
	set s_lno [$ui_diff search -backwards -regexp ^@@ $s_lno.0 0.0]
	if {$s_lno eq {}} {
		unlock_index
		return
	}

	set e_lno [$ui_diff search -forwards -regexp ^@@ "$s_lno + 1 lines" end]
	if {$e_lno eq {}} {
		set e_lno end
	}

	if {[catch {
		set enc [get_path_encoding $current_diff_path]
		set p [eval git_write $apply_cmd]
		fconfigure $p -translation binary -encoding $enc
		puts -nonewline $p $current_diff_header
		puts -nonewline $p [$ui_diff get $s_lno $e_lno]
		close $p} err]} {
		error_popup [append $failed_msg "\n\n$err"]
		unlock_index
		return
	}

	$ui_diff conf -state normal
	$ui_diff delete $s_lno $e_lno
	$ui_diff conf -state disabled

	if {[$ui_diff get 1.0 end] eq "\n"} {
		set o _
	} else {
		set o ?
	}

	if {$current_diff_side eq $ui_index} {
		set mi ${o}M
	} elseif {[string index $mi 0] eq {_}} {
		set mi M$o
	} else {
		set mi ?$o
	}
	unlock_index
	display_file $current_diff_path $mi
	# This should trigger shift to the next changed file
	if {$o eq {_}} {
		reshow_diff
	}
}

proc apply_line {x y} {
	global current_diff_path current_diff_header current_diff_side
	global ui_diff ui_index file_states

	if {$current_diff_path eq {} || $current_diff_header eq {}} return
	if {![lock_index apply_hunk]} return

	set apply_cmd {apply --cached --whitespace=nowarn}
	set mi [lindex $file_states($current_diff_path) 0]
	if {$current_diff_side eq $ui_index} {
		set failed_msg [mc "Failed to unstage selected line."]
		set to_context {+}
		lappend apply_cmd --reverse
		if {[string index $mi 0] ne {M}} {
			unlock_index
			return
		}
	} else {
		set failed_msg [mc "Failed to stage selected line."]
		set to_context {-}
		if {[string index $mi 1] ne {M}} {
			unlock_index
			return
		}
	}

	set the_l [$ui_diff index @$x,$y]

	# operate only on change lines
	set c1 [$ui_diff get "$the_l linestart"]
	if {$c1 ne {+} && $c1 ne {-}} {
		unlock_index
		return
	}
	set sign $c1

	set i_l [$ui_diff search -backwards -regexp ^@@ $the_l 0.0]
	if {$i_l eq {}} {
		unlock_index
		return
	}
	# $i_l is now at the beginning of a line

	# pick start line number from hunk header
	set hh [$ui_diff get $i_l "$i_l + 1 lines"]
	set hh [lindex [split $hh ,] 0]
	set hln [lindex [split $hh -] 1]

	# There is a special situation to take care of. Consider this hunk:
	#
	#    @@ -10,4 +10,4 @@
	#     context before
	#    -old 1
	#    -old 2
	#    +new 1
	#    +new 2
	#     context after
	#
	# We used to keep the context lines in the order they appear in the
	# hunk. But then it is not possible to correctly stage only
	# "-old 1" and "+new 1" - it would result in this staged text:
	#
	#    context before
	#    old 2
	#    new 1
	#    context after
	#
	# (By symmetry it is not possible to *un*stage "old 2" and "new 2".)
	#
	# We resolve the problem by introducing an asymmetry, namely, when
	# a "+" line is *staged*, it is moved in front of the context lines
	# that are generated from the "-" lines that are immediately before
	# the "+" block. That is, we construct this patch:
	#
	#    @@ -10,4 +10,5 @@
	#     context before
	#    +new 1
	#     old 1
	#     old 2
	#     context after
	#
	# But we do *not* treat "-" lines that are *un*staged in a special
	# way.
	#
	# With this asymmetry it is possible to stage the change
	# "old 1" -> "new 1" directly, and to stage the change
	# "old 2" -> "new 2" by first staging the entire hunk and
	# then unstaging the change "old 1" -> "new 1".

	# This is non-empty if and only if we are _staging_ changes;
	# then it accumulates the consecutive "-" lines (after converting
	# them to context lines) in order to be moved after the "+" change
	# line.
	set pre_context {}

	set n 0
	set i_l [$ui_diff index "$i_l + 1 lines"]
	set patch {}
	while {[$ui_diff compare $i_l < "end - 1 chars"] &&
	       [$ui_diff get $i_l "$i_l + 2 chars"] ne {@@}} {
		set next_l [$ui_diff index "$i_l + 1 lines"]
		set c1 [$ui_diff get $i_l]
		if {[$ui_diff compare $i_l <= $the_l] &&
		    [$ui_diff compare $the_l < $next_l]} {
			# the line to stage/unstage
			set ln [$ui_diff get $i_l $next_l]
			if {$c1 eq {-}} {
				set n [expr $n+1]
				set patch "$patch$pre_context$ln"
			} else {
				set patch "$patch$ln$pre_context"
			}
			set pre_context {}
		} elseif {$c1 ne {-} && $c1 ne {+}} {
			# context line
			set ln [$ui_diff get $i_l $next_l]
			set patch "$patch$pre_context$ln"
			set n [expr $n+1]
			set pre_context {}
		} elseif {$c1 eq $to_context} {
			# turn change line into context line
			set ln [$ui_diff get "$i_l + 1 chars" $next_l]
			if {$c1 eq {-}} {
				set pre_context "$pre_context $ln"
			} else {
				set patch "$patch $ln"
			}
			set n [expr $n+1]
		}
		set i_l $next_l
	}
	set patch "@@ -$hln,$n +$hln,[eval expr $n $sign 1] @@\n$patch"

	if {[catch {
		set enc [get_path_encoding $current_diff_path]
		set p [eval git_write $apply_cmd]
		fconfigure $p -translation binary -encoding $enc
		puts -nonewline $p $current_diff_header
		puts -nonewline $p $patch
		close $p} err]} {
		error_popup [append $failed_msg "\n\n$err"]
	}

	unlock_index
}

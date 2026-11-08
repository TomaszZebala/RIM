# =============================================================================
# Odtwarza projekt Vivado RIM od zera.
#
# Uzycie (z katalogu glownego repo):
#   vivado -mode batch -source scripts/create_project.tcl
# lub w GUI Vivado: Tools -> Run Tcl Script... -> scripts/create_project.tcl
#
# Projekt powstaje w katalogu build/ (ignorowanym przez git).
# Zrodla HDL NIE sa kopiowane - projekt wskazuje bezposrednio na pliki w hdl/,
# wiec edycje w Vivado laduja od razu w repo.
# =============================================================================

set proj_name   rim_proj
set bd_name     rim_proj_hw
set part        xc7z010clg400-1
set board_part  digilentinc.com:cora-z7-10:part0:1.1

set repo_dir  [file normalize [file join [file dirname [info script]] ..]]
set build_dir [file join $repo_dir build]

if {[file exists [file join $build_dir $proj_name.xpr]]} {
    puts "ERROR: Projekt juz istnieje w $build_dir. Usun katalog build/ i uruchom ponownie."
    return -code error
}

# Board files pobrane przez GUI (Xilinx Board Store) leza w ~/.Xilinx i tryb
# batch ich nie widzi - dodajemy te sciezke, jesli istnieje.
set vver [version -short]
set xhub_store [file normalize "~/.Xilinx/Vivado/$vver/xhub/board_store/xilinx_board_store"]
if {[file isdirectory $xhub_store]} {
    set_param board.repoPaths [concat [get_param board.repoPaths] [list $xhub_store]]
}

create_project $proj_name $build_dir -part $part

# Plytka Cora Z7-10 - opcjonalnie. Konfiguracja PS7 jest w calosci zapisana
# w skrypcie BD, wiec bez board files projekt i tak zbuduje sie poprawnie.
if {[llength [get_board_parts -quiet $board_part]] > 0} {
    set_property board_part $board_part [current_project]
} else {
    puts "WARNING: Brak board files dla $board_part - uzywam samego partu $part."
}

set_property target_language    Verilog [current_project]
set_property simulator_language Mixed   [current_project]

# --- Zrodla HDL (moduly uzywane w BD jako module reference) -----------------
add_files -norecurse [glob [file join $repo_dir hdl *.v]]
update_compile_order -fileset sources_1

# --- Ograniczenia (jesli kiedys sie pojawia) --------------------------------
set xdc_files [glob -nocomplain [file join $repo_dir constrs *.xdc]]
if {[llength $xdc_files] > 0} {
    add_files -fileset constrs_1 -norecurse $xdc_files
}

# --- Block design ------------------------------------------------------------
source [file join $repo_dir bd $bd_name.tcl]
cr_bd_${bd_name} ""

set bd_file [get_files $bd_name.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "INFO: Projekt gotowy: [file join $build_dir $proj_name.xpr]"

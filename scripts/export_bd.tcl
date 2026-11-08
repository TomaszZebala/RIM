# =============================================================================
# Zapisuje aktualny block design z projektu w build/ do bd/rim_proj_hw.tcl.
# Uruchom PO KAZDEJ zmianie w block designie, zanim zrobisz commit.
#
# Uzycie:
#   - w GUI (z otwartym projektem): Tcl Console ->
#       source <repo>/scripts/export_bd.tcl
#   - z terminala:
#       vivado -mode batch -source scripts/export_bd.tcl
# =============================================================================

set proj_name rim_proj
set bd_name   rim_proj_hw

set repo_dir [file normalize [file join [file dirname [info script]] ..]]

if {[catch {current_project}]} {
    open_project [file join $repo_dir build $proj_name.xpr]
}

open_bd_design [get_files $bd_name.bd]
write_bd_tcl -force -include_layout -no_project_wrapper \
    [file join $repo_dir bd $bd_name.tcl]
puts "INFO: Zapisano bd/$bd_name.tcl"

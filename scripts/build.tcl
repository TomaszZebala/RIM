# =============================================================================
# Pelny build: synteza -> implementacja -> bitstream -> eksport .xsa
#
# Uzycie (z katalogu glownego repo):
#   vivado -mode batch -source scripts/build.tcl
#
# Jesli projekt w build/ nie istnieje, najpierw zostanie utworzony.
# Wynik: build/rim_proj_hw_wrapper.xsa (z bitstreamem, do Vitisa / PYNQ itp.)
# =============================================================================

set proj_name rim_proj
set bd_name   rim_proj_hw
set jobs      4

set repo_dir  [file normalize [file join [file dirname [info script]] ..]]
set build_dir [file join $repo_dir build]
set xpr       [file join $build_dir $proj_name.xpr]

if {[file exists $xpr]} {
    open_project $xpr
} else {
    source [file join $repo_dir scripts create_project.tcl]
}

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "ERROR: Implementacja nie zakonczyla sie poprawnie."
    return -code error
}

set xsa [file join $build_dir ${bd_name}_wrapper.xsa]
write_hw_platform -fixed -include_bit -force -file $xsa
puts "INFO: Gotowe: $xsa"

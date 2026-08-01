"""
Build opencore-amr NB (encoder+decoder) and WB (decoder) as MSVC static libs.
Produces:
    third_party/opencore-amr/lib/opencore-amrnb.lib
    third_party/opencore-amr/lib/opencore-amrwb.lib
And copies headers to:
    third_party/opencore-amr/include/opencore-amrnb/
    third_party/opencore-amr/include/opencore-amrwb/
"""
import os, subprocess, shutil, sys
from concurrent.futures import ThreadPoolExecutor

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
oc_root = os.path.join(root, 'third_party', 'opencore-amr')
amr_base = os.path.join(oc_root, 'opencore', 'codecs_v2', 'audio', 'gsm_amr')

cl_bin = r'D:\msvc\VC\Tools\MSVC\14.44.35207\bin\HostX64\x64\cl.exe'
lib_bin = r'D:\msvc\VC\Tools\MSVC\14.44.35207\bin\HostX64\x64\lib.exe'

# MSVC system includes
sys_inc = [
    r'D:\msvc\VC\Tools\MSVC\14.44.35207\include',
    r'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\ucrt',
    r'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\um',
    r'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared',
]

oscl_dir = os.path.join(oc_root, 'oscl')

# ---- AMR-NB ----
nb_dec_src = os.path.join(amr_base, 'amr_nb', 'dec', 'src')
nb_enc_src = os.path.join(amr_base, 'amr_nb', 'enc', 'src')
nb_common_src = os.path.join(amr_base, 'amr_nb', 'common', 'src')

nb_inc_dirs = [
    oscl_dir,
    nb_dec_src,
    os.path.join(amr_base, 'amr_nb', 'common', 'include'),
    os.path.join(amr_base, 'amr_nb', 'dec', 'include'),
    os.path.join(amr_base, 'common', 'dec', 'include'),
    nb_enc_src,
] + sys_inc

# Decoder sources (from Makefile.am)
nb_dec_files = [
    'agc.cpp', 'amrdecode.cpp', 'a_refl.cpp', 'b_cn_cod.cpp', 'bgnscd.cpp',
    'c_g_aver.cpp', 'd1035pf.cpp', 'd2_11pf.cpp', 'd2_9pf.cpp', 'd3_14pf.cpp',
    'd4_17pf.cpp', 'd8_31pf.cpp', 'dec_amr.cpp', 'dec_gain.cpp',
    'dec_input_format_tab.cpp', 'dec_lag3.cpp', 'dec_lag6.cpp', 'd_gain_c.cpp',
    'd_gain_p.cpp', 'd_plsf_3.cpp', 'd_plsf_5.cpp', 'd_plsf.cpp', 'dtx_dec.cpp',
    'ec_gains.cpp', 'ex_ctrl.cpp', 'if2_to_ets.cpp', 'int_lsf.cpp', 'lsp_avg.cpp',
    'ph_disp.cpp', 'post_pro.cpp', 'preemph.cpp', 'pstfilt.cpp', 'qgain475_tab.cpp',
    'sp_dec.cpp', 'wmf_to_ets.cpp',
]

# Encoder sources
nb_enc_files = [
    'amrencode.cpp', 'autocorr.cpp', 'c1035pf.cpp', 'c2_11pf.cpp', 'c2_9pf.cpp',
    'c3_14pf.cpp', 'c4_17pf.cpp', 'c8_31pf.cpp', 'calc_cor.cpp', 'calc_en.cpp',
    'cbsearch.cpp', 'cl_ltp.cpp', 'cod_amr.cpp', 'convolve.cpp', 'cor_h.cpp',
    'cor_h_x2.cpp', 'cor_h_x.cpp', 'corrwght_tab.cpp', 'div_32.cpp', 'dtx_enc.cpp',
    'enc_lag3.cpp', 'enc_lag6.cpp', 'enc_output_format_tab.cpp', 'ets_to_if2.cpp',
    'ets_to_wmf.cpp', 'g_adapt.cpp', 'gain_q.cpp', 'g_code.cpp', 'g_pitch.cpp',
    'hp_max.cpp', 'inter_36.cpp', 'inter_36_tab.cpp', 'l_abs.cpp', 'lag_wind.cpp',
    'lag_wind_tab.cpp', 'l_comp.cpp', 'levinson.cpp', 'l_extract.cpp', 'lflg_upd.cpp',
    'l_negate.cpp', 'lpc.cpp', 'ol_ltp.cpp', 'pitch_fr.cpp', 'pitch_ol.cpp',
    'p_ol_wgh.cpp', 'pre_big.cpp', 'pre_proc.cpp', 'prm2bits.cpp', 'qgain475.cpp',
    'qgain795.cpp', 'q_gain_c.cpp', 'q_gain_p.cpp', 'qua_gain.cpp', 's10_8pf.cpp',
    'set_sign.cpp', 'sid_sync.cpp', 'sp_enc.cpp', 'spreproc.cpp', 'spstproc.cpp',
    'ton_stab.cpp', 'vad1.cpp',
]

# Common sources
nb_common_files = [
    'add.cpp', 'az_lsp.cpp', 'bitno_tab.cpp', 'bitreorder_tab.cpp', 'c2_9pf_tab.cpp',
    'div_s.cpp', 'extract_h.cpp', 'extract_l.cpp', 'gains_tbl.cpp', 'gc_pred.cpp',
    'get_const_tbls.cpp', 'gmed_n.cpp', 'gray_tbl.cpp', 'grid_tbl.cpp', 'int_lpc.cpp',
    'inv_sqrt.cpp', 'inv_sqrt_tbl.cpp', 'l_deposit_h.cpp', 'l_deposit_l.cpp',
    'log2.cpp', 'log2_norm.cpp', 'log2_tbl.cpp', 'lsfwt.cpp', 'l_shr_r.cpp',
    'lsp_az.cpp', 'lsp.cpp', 'lsp_lsf.cpp', 'lsp_lsf_tbl.cpp', 'lsp_tab.cpp',
    'mult_r.cpp', 'negate.cpp', 'norm_l.cpp', 'norm_s.cpp', 'overflow_tbl.cpp',
    'ph_disp_tab.cpp', 'pow2.cpp', 'pow2_tbl.cpp', 'pred_lt.cpp', 'q_plsf_3.cpp',
    'q_plsf_3_tbl.cpp', 'q_plsf_5.cpp', 'q_plsf_5_tbl.cpp', 'q_plsf.cpp',
    'qua_gain_tbl.cpp', 'reorder.cpp', 'residu.cpp', 'round.cpp', 'set_zero.cpp',
    'shr.cpp', 'shr_r.cpp', 'sqrt_l.cpp', 'sqrt_l_tbl.cpp', 'sub.cpp',
    'syn_filt.cpp', 'weight_a.cpp', 'window_tab.cpp',
]

# ---- AMR-WB (decoder only) ----
wb_dec_src = os.path.join(amr_base, 'amr_wb', 'dec', 'src')
wb_inc_dirs = [
    oscl_dir,
    wb_dec_src,
    os.path.join(amr_base, 'amr_wb', 'dec', 'include'),
    os.path.join(amr_base, 'common', 'dec', 'include'),
] + sys_inc

wb_dec_files = [
    'agc2_amr_wb.cpp', 'band_pass_6k_7k.cpp', 'dec_acelp_2p_in_64.cpp',
    'dec_acelp_4p_in_64.cpp', 'dec_alg_codebook.cpp', 'dec_gain2_amr_wb.cpp',
    'deemphasis_32.cpp', 'dtx_decoder_amr_wb.cpp', 'get_amr_wb_bits.cpp',
    'highpass_400hz_at_12k8.cpp', 'highpass_50hz_at_12k8.cpp',
    'homing_amr_wb_dec.cpp', 'interpolate_isp.cpp', 'isf_extrapolation.cpp',
    'isp_az.cpp', 'isp_isf.cpp', 'lagconceal.cpp', 'low_pass_filt_7k.cpp',
    'median5.cpp', 'mime_io.cpp', 'noise_gen_amrwb.cpp', 'normalize_amr_wb.cpp',
    'oversamp_12k8_to_16k.cpp', 'phase_dispersion.cpp', 'pit_shrp.cpp',
    'pred_lt4.cpp', 'preemph_amrwb_dec.cpp', 'pvamrwbdecoder.cpp',
    'pvamrwb_math_op.cpp', 'q_gain2_tab.cpp', 'qisf_ns.cpp', 'qisf_ns_tab.cpp',
    'qpisf_2s.cpp', 'qpisf_2s_tab.cpp', 'scale_signal.cpp',
    'synthesis_amr_wb.cpp', 'voice_factor.cpp', 'wb_syn_filt.cpp',
    'weight_amrwb_lpc.cpp',
]

# ---- Build functions ----
obj_dir = os.path.join(oc_root, 'obj')
lib_dir = os.path.join(oc_root, 'lib')
inc_out = os.path.join(oc_root, 'include')

os.makedirs(obj_dir, exist_ok=True)
os.makedirs(lib_dir, exist_ok=True)

def compile_file(args):
    idx, src, inc_dirs, prefix = args
    base = os.path.basename(src).replace('.cpp', '.obj')
    obj = os.path.join(obj_dir, f'{prefix}_{idx}_{base}')
    inc_cmd = ' '.join(f'/I"{d}"' for d in inc_dirs)
    # Compile as C++ with /TP, suppress warnings with /W0
    cmd = f'"{cl_bin}" /c /O2 /nologo /W0 /EHsc /TP {inc_cmd} "{src}" /Fo"{obj}"'
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  FAIL: {os.path.basename(src)}: {r.stderr[:150]}")
        return None
    return obj

def build_lib(name, sources, inc_dirs, prefix):
    print(f"\nCompiling {name} ({len(sources)} files)...")
    items = [(i, s, inc_dirs, prefix) for i, s in enumerate(sources)]
    with ThreadPoolExecutor(max_workers=8) as pool:
        objs = list(pool.map(compile_file, items))
    valid = [o for o in objs if o]
    print(f"  Compiled {len(valid)}/{len(sources)} files")
    if not valid:
        print(f"  ERROR: No object files for {name}")
        return False
    lib_path = os.path.join(lib_dir, f'{name}.lib')
    rsp = os.path.join(obj_dir, f'{name}.rsp')
    with open(rsp, 'w') as f:
        for o in valid:
            f.write(f'"{o}"\n')
    cmd = f'"{lib_bin}" /nologo /OUT:"{lib_path}" @"{rsp}"'
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  LIB error: {r.stderr[:300]}")
        return False
    sz = os.path.getsize(lib_path)
    print(f"  Created {lib_path} ({sz:,} bytes)")
    return True

def copy_headers():
    """Copy public headers so pjmedia can find them as <opencore-amrnb/interf_enc.h>"""
    nb_inc = os.path.join(inc_out, 'opencore-amrnb')
    wb_inc = os.path.join(inc_out, 'opencore-amrwb')
    os.makedirs(nb_inc, exist_ok=True)
    os.makedirs(wb_inc, exist_ok=True)
    # AMR-NB headers
    for h in ['interf_enc.h', 'interf_dec.h']:
        src = os.path.join(oc_root, 'amrnb', h)
        if os.path.exists(src):
            shutil.copy2(src, nb_inc)
    # AMR-WB headers
    for h in ['dec_if.h', 'if_rom.h']:
        src = os.path.join(oc_root, 'amrwb', h)
        if os.path.exists(src):
            shutil.copy2(src, wb_inc)
    print(f"Headers copied to {inc_out}")

# ---- Main ----
if __name__ == '__main__':
    print("Building OpenCORE AMR static libraries for MSVC x64...")

    # Gather NB sources
    nb_sources = [os.path.join(oc_root, 'amrnb', 'wrapper.cpp')]
    nb_sources += [os.path.join(nb_dec_src, f) for f in nb_dec_files]
    nb_sources += [os.path.join(nb_enc_src, f) for f in nb_enc_files]
    nb_sources += [os.path.join(nb_common_src, f) for f in nb_common_files]

    ok_nb = build_lib('opencore-amrnb', nb_sources, nb_inc_dirs, 'nb')

    # Gather WB sources
    wb_sources = [os.path.join(oc_root, 'amrwb', 'wrapper.cpp')]
    wb_sources += [os.path.join(wb_dec_src, f) for f in wb_dec_files]

    ok_wb = build_lib('opencore-amrwb', wb_sources, wb_inc_dirs, 'wb')

    copy_headers()

    if ok_nb and ok_wb:
        print("\n=== SUCCESS: Both AMR-NB and AMR-WB libs built! ===")
    elif ok_nb:
        print("\n=== PARTIAL: AMR-NB built, AMR-WB failed ===")
    else:
        print("\n=== FAILED ===")
        sys.exit(1)

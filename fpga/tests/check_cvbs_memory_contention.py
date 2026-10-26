from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sources=['tests/tb_cvbs_boink_pixels.sv','tests/cvbs_contended_memory.sv','src/coco3/gime_scanline_buffer.v','src/coco3/coco3_char_rom.v','src/video/ntsc_artifact_decode.v','src/cvbs/video/coco_cvbs_ntsc.v','src/coco3/gime_timing.v','src/memory/coco3_memory.v','src/memory/cpu_sdram_arbiter.v','src/memory/coco_sdram_startup_test.v','src/memory/coco_flash_loader.v','src/memory/spi_flash_reader.v']
def main():
 with tempfile.TemporaryDirectory(prefix="cocotang-cvbs-contention-") as directory:
  for tag,controller in [('original','src/memory/sdram.v')]:
   for fast in [0,1]:
    binary=str(Path(directory)/f'{tag}-{fast}')
    args=['iverilog','-g2012','-s','tb_cvbs_boink_pixels',
          '-Ptb_cvbs_boink_pixels.REAL_MEMORY=1',
          f'-Ptb_cvbs_boink_pixels.FAST={fast}',
          '-Ptb_cvbs_boink_pixels.ROWS=225','-o',binary]+sources+[controller]
    subprocess.run(args,cwd=ROOT,check=True)
    run=subprocess.run(['vvp',binary],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    print(f'{tag}, fast={fast}: {run.stdout}',end='',flush=True)
    run.check_returncode()


if __name__ == '__main__':
 main()

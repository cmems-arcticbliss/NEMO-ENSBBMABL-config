#!/bin/bash
# 
module purge
module load gcc/9.1.0
module load intel-all
module load gcc/9.1.0
module load hdf5/1.10.5-mpi
module load netcdf/4.7.2-mpi
module load netcdf-fortran/4.5.2-mpi

echo " you can now run:  srun -p compil -c 10 --hint=nomultithread --account=cli@cpu ./makenemo -m JZ-SLX -r NANUK4_ICE_ABL -j 8"
echo " or remove option -p compil if you wish"

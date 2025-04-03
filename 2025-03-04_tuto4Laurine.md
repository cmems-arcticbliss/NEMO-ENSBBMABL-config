Purpose: Tutorial to help Laurine start with our Arctic-BLISS NEMO-SI3+ABL config on Jean-Zay@IDRIS.

### On JZ: Make sure you have the same environment as me on JZ (important for later compilation of the codes)
```
# TO COMPILE XIOS and NEMO 24th of AUG 2023

module purge
module load gcc/9.1.0
module load intel-all
module load gcc/9.1.0
module load hdf5/1.10.5-mpi
module load netcdf/4.7.2-mpi
module load netcdf-fortran/4.5.2-mpi
#module load python/3.8.8
module load ncview
module load nco
```

---
### On the WORK space of JZ:

1. __Copy sources of XIOS, NEMO, the config manager and misc stuff__

```
# go to work space and create DEVGIT and DEV directories if do not exist already
cd $WORK
mkdir -p DEVGIT
mkdir -p DEV

# clone XIOS
cd $WORK/DEV
svn co http://forge.ipsl.jussieu.fr/ioserver/svn/XIOS/trunk@2320 xios-trunk-2320

# clone NEMO official release 4.2.2
cd $WORK/DEVGIT
mkdir NEMO
cd NEMO
git clone --branch 4.2.2 https://forge.nemo-ocean.eu/nemo/nemo.git NEMOGCM_4.2.2

# clone Arctic-BLISS sources
cd $WORK/DEVGIT
mkdir -p ArcticBLISS-all
cd ArcticBLISS-all
git clone https://github.com/cmems-arcticbliss/NEMO-ENSBBMABL-config.git


# [Pour Laurine on JZ:] copy Laurent Brodeau's nemo_config manager from my space:
cd $WORK/DEVGIT/
cp -r /lustre/fsn1/projects/rech/cli/regi915/TEST-LF-NEMO/nemo_conf_manager/ .

```

---
2. __Compile XIOS__
```
cd $WORK/DEVGIT
cd  xios-trunk-2430

srun -p compil -c 10 --hint=nomultithread --account=cli@cpu ./make_xios --arch X64_JEANZAY --full --prod --job 10
```

---
3. __nemo_conf_manager__
* Need to check some paths and links but in principle it should be work as is if things have been installed at the same location as mine.
```
cd $WORK/DEVGIT/nemo_conf_manager

# check link to xios
cd nemo_conf_manager/ARCH
vi arch-JZ-SLX.fcm

# check paths to data
cd nemo_conf_manager/CONFS/
vi HOSTS.bash

# check path to NEMO and nemo_conf_manager
cd nemo_conf_manager/CONFS/NANUK4_ICE_ABL
vi setup.bash

# check script to make the config. 
cd nemo_conf_manager
vi create_conf_SLX.sh
```

* create a config:

```
cd $WORK/DEVGIT/nemo_conf_manager

./create_conf_SLX.sh -C NANUK4_ICE_ABL -V 4.2.2 -A JZ-SLX -i ENSBBMABL
```

It will create a directory `$WORK/NEMO/NEMOv4.2.2_ENSBBMABL` where the official code is copied and named with the same tag as you used with the create_conf script (tag = ENSBBMABL). This is where you will compile the code for your configuration. 


* Go to code compilation directory and link new sources in MY_SRC (sources that are modified compared to the official 4.2.2 release and must be taken into account at compilation).
```
cd $WORK/NEMO/NEMOv4.2.2_BBMABL/cfgs/NANUK4_ICE_ABL/MY_SRC

ln -sf $WORK/ArcticBLISS-all/NEMO-ENSBBMABL/MY_SRC/* .
```

---
4. __Compile NEMO:__
```
# go to compilation directory
cd $WORK/NEMO/NEMOv4.2.2_BBMABL/

# copy script to remind yourself the compilation line
cp $WORK/ArcticBLISS-all/NEMO-ENSBBMABL/MY_config/compile_NANUK4_ICE_ABL_SLX.sh .

# run:
./compile_NANUK4_ICE_ABL_SLX.sh 

# copy-paste the command
srun -p compil -c 10 --hint=nomultithread --account=cli@cpu ./makenemo -m JZ-SLX -r NANUK4_ICE_ABL -j 8

# you can also try without the -p compil option
```

Now your code is all gathered in :
`$WORK/NEMO/NEMOv4.2.2_ENSBBMABL/cfgs/NANUK4_ICE_ABL/WORK`

And you executable is there :
`$WORK/NEMO/NEMOv4.2.2_ENSBBMABL/cfgs/NANUK4_ICE_ABL/BLD/bin/nemo.exe`

---
5. __Add some shortcuts__

I suggest that you add some shortcuts in your .bashrc. For example:
```
alias recapabl='echo "ctlabl compilabl outabl rstabl frcabl Iabl prodabl" '
alias ctlabl='cd $WORK/DEVGIT/nemo_conf_manager/TEST_RUN/NANUK4/TEST_NANUK4_4.2/'
alias compilabl='cd $WORK/NEMO/'                                   
alias outabl='cd $SCRATCH/NEMO/NANUK4'
alias outablCOM='cd $ALL_CCFRSTORE/NANUK4'
alias rstabl='cd $STORE/NEMO/NANUK4'
alias rstablCOM='cd $ALL_CCFRSTORE/NEMO/NANUK4'                                   
alias frcabl='cd $ALL_CCFRSTORE/NANUK4/DATASETS/atmo_forcing'
alias Iabl='cd $ALL_CCFRSTORE/NANUK4/NANUK4.L31-I'                                  
alias prodabl='cd $SCRATCH/NEMO/tmp/NANUK4/'
```


---
## Prepare an ensemble simulation:

1. __Recap:__
* All the experiments you will produce will be installed and launched from here: 
`cd $WORK/nemo_conf_manager/TEST_RUN/NANUK4/TEST_NANUK4_4.2/`

* The experiments run on the SCRATCH space: `$SCRATCH/NEMO/tmp/NANUK4/`
* Once the experiment has run and is successful, the outputs and restarts are copied there: `$SCRATCH/NEMO/NANUK4` on your SCRATCH space. You will need to copy them on the common STORE space afterwards (`$ALL_CCFRSTORE/NANUK4`)

2. __Let’s take the example of `EABLBBM110`:__

* Prep	 files if needed:
Most files are already accessible from SCRATCH/common:
* (forcing) `$ALL_CCFRSTORE/DATA/` 
* and (restarts) `$ALL_CCFRSTORE/NEMO/NANUK4/`
I `touch` them regularly to keep them on the scratch space but in case there are also on the STORE/common (but not accessible from the computing nodes, which is why we have to keep them copied on the SCRATCH space.

* Gather files:
```
cd $WORK/nemo_conf_manager/TEST_RUN/NANUK4/TEST_NANUK4_4.2/EABLBBM110
mkdir Namelists
cd Namelists

# link xml files
ln -sf  $WORK/DEVGIT/ArcticBLISS-all/NEMO-ENSBBMABL-config/MY_config/*.xml .

# link reference namelists
ln -sf $WORK/DEVGIT/ArcticBLISS-all/NEMO-ENSBBMABL-config/MY_config/namelist*_ref .

# copy namelist_cfg so that you can edit individually if needed
cp $WORK/DEVGIT/ArcticBLISS-all/NEMO-ENSBBMABL-config/MY_config/namelist*cfg .
```

* the script to prepare and launch the simulation is:
```
cd $WORK/nemo_conf_manager/TEST_RUN/NANUK4/TEST_NANUK4_4.2/EABLBBM110
vi NANUK4_ICE_ABL-EABLBBM110.sh
```
This is where you set the length of the simulation, the frequency of the outputs, etc…
To run the simulation on a computing node, just run: `./NANUK4_ICE_ABL-EABLBBM110.sh`
To check if it is pending or running: `squeue -u regi915`

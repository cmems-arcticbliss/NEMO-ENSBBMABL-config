#!/bin/bash

#NCM_DIR="${HOME}/DEV/nemo_conf_manager"
# SLX
NCM_DIR="${WORK}/DEVGIT/nemo_conf_manager"

ABLDIR="/lustre/fsn1/projects/rech/cli/regi915/DATA/NANUK4/DATASETS/atmo_forcing/ERA5_ABL_from_GS/1h"
i_skip_link_restarts=0

myRSTDIR="/lustre/fsn1/projects/rech/cli/regi915/NEMO/NANUK4/NANUK4_ICE_ABL-EABLBBM000-R/00004800_perturbed/"

# Getting a lot of info from the HOSTS.bash file:
. ${NCM_DIR}/CONFS/HOSTS.bash

. ${NCM_DIR}/misc/lb_functions.sh

MOD_TO_LOAD=""

ltide=false

lmenage_node=false

isi3=1 ; # SI3 or not?
isas=0 ; # SAS or not?
ioa3=0 ; # OASIS or not?
inxs=0 ; # coupled to neXtSIM via OASIS or not?
iagr=0 ; NST_RAT=0 ; CONF_NST="" ; # AGRIF? + resolution ratio CHILD/MOTHER
itst=0 ; # testcase or real config?
isabl=1 ; # ABL or not?

# namelist
LNABL="true"
LNBLK="false"

RSTABL="true"

# namelist_ice
LNEVP="false"
LNBBM="true"
LNDAM="true"
CDice="1.85e-3"

# stochastic part (in namelist_cfg)
LNENS="true"
LNENSRST="true"
LNSTOEOS="false"
MEMBER0=1
MEMBERN=20
NMEMBER=$(( MEMBERN - MEMBER0 + 1 ))
echo "NMEMBER = $NMEMBER"

perturbnam=l500_std50_interplinear_perturbed_lgrid10sm3_SD1800.nc
myRSTIT=1800
myRSTPREFIX="NANUK4_ICE_ABL-EABLBBM000_0000"


# compute cores and nodes requested for the ensemble simulation
NPROCsingle=38     # nb of procs for one member simulation
NPROCJZNODE=40     # nb of procs on one node on Jean Zay
NCORES_NEM=$(( $NPROCsingle * $NMEMBER ))    # total nuùber of requested cores for a $NMEMBER ensemble simulation
echo $NPROCsingle
echo $NMEMBER
echo $NCORES_NEM

# compute the corresponding number of requested nodes:
# Compute the integer division and remainder
NNODES=$(( NCORES_NEM / NPROCJZNODE ))
remainder=$(( NCORES_NEM % NPROCJZNODE ))
# If there's a remainder, increment the result
if (( remainder > 0 )); then
    NNODES=$(( NNODES + 1 ))
fi
echo "NNODES:"
echo $NNODES

IDEBUG=1

init_ice=0  # SLX ; # (if isi3==1) set to `1` if you want to initialize sea-ice frome netCDF fields, 0 otherwize!

NM_ATM_FORC="ERA5_Arctic"

NEMOv="4.2.2"     ; crdt='rn_Dt'  ; naaa=4
CID="_ENSBBMABL"


# Time stuff:
Y1=1997 ; Y2=1997
#M1=1    ; # start month of year Y1
M1=1   ; # start month of year Y1
#
LENGTH_SEG="10d" ;
#LENGTH_SEG="49d" ; # something like "1d", "5d", "10d", "15d", "1m", "3m", "6m", or "1y"
RESTRT_FRQ="10d" ; # something like "1d", "5d", "10d", "15d", "1m", "3m", "6m", or "1y"
#LENGTH_SEG="10d" ; # something like "1d", "5d", "10d", "15d", "1m", "3m", "6m", or "1y"
#RESTRT_FRQ="10d" ; # something like "1d", "5d", "10d", "15d", "1m", "3m", "6m", or "1y"

xios_freq_oce="prodArcticBLISS"
xios_freq_ice="prodArcticBLISS"
#xios_freq_oce="1d"
#xios_freq_ice="prodSLX"


TJOB="01:20:00" # Max wall length for the job
#TJOB="00:55:00" # Max wall length for the job

IBC="GLORYS2V4" ; # origin of 3D initial condition fields for cold start...
BDY="GLORYS2V4" ; # origin of lateral BC fields if relevant...

RNF="" ; # when inter-annual forcing...

CONF="NANUK4" ; # Config as in the "${CONF}/${CONF}-I" or "${CONF}/${CONF}.L${NZ}-I" directory...
NZ="31"       ; # number of levels
DT="720" ; #12 min ; # NEMO time step in seconds
force_fsbc=1  ; # if >= 1 then we shall force this FSBC, otherwize it will be deduced from the freq of the Atmo forcing (FRQ_EC)

# neXtSIM stuff:
MSH_FILE_NXS="nanuk4_cpl.msh" ; # mesh file to use for neXtSIM (must be present into ${DATA_CONF_DIR}/NEXTSIM/)
NXS_BRANCH="develop" ;          # neXtSIM branch to use (will look for exec in  `nextsim_${NXS_BRANCH}`)

LIST_F90_BKP="lib_mpp mppini nemogcm stopar storng stoctl domain dom_oce sbcblk sbcabl ablmod ablrst icedyn_rhg_bbm icedyn_adv icedyn_adv_umx icedyn_adv_pra icedyn_rhg_util iceupdate" ; # list of pre-processed NEMO sources to backup in SAVE directory

#===================================================================================================================

isas_cpl=0
isas_ssx=0
if [ ${isas} -eq 1 ]; then
    if [ ${ioa3} -eq 1 ]; then
        isas_cpl=1 ; # SAS coupled to OPA via oasis !!!
    else
        isas_ssx=1 ; # SAS using prescribed SS* fields in netCDF files...
    fi
fi

if [ ${iagr} -eq 1 ]; then DT_n=$((DT/NST_RAT)); fi
if [ ${ioa3} -eq 1 ]; then DT_SIA=${DT} ;        fi          # neXtSIM time step in seconds


NV=`echo ${NEMOv} | cut -c1-1` ; # NEMO version short / 1 character: "3", "4", etc
case ${NV} in
    "3")   NM_ICEXT="LIM3"
           NM_DARCH="ARCH"
           NM_DCONF="CONFIG"
         ;;
    "4"|"g") NM_ICEXT="ICE"
           NM_DARCH="arch"
           NM_DCONF="cfgs"
           ;;
    *) echo "UNKNOWN version of NEMO: ${NV} !!!"
       exit
       ;;
esac

CONFL="${CONF}"
if [ ${isi3} -eq 1 ] && [ ${isas} -ne 1 ]; then CONFL="${CONFL}_${NM_ICEXT}"; fi
if [ ${isas} -eq 1 ] && [ ${isi3} -eq 1 ]; then CONFL="${CONFL}_SAS_ICE";    NSIA="SAS"    ; NMSIA="SAS-SI3"; fi
if [ ${isas} -eq 1 ] && [ ${isi3} -ne 1 ]; then CONFL="${CONFL}_SAS";        NSIA="SAS"    ; NMSIA="SAS"; fi
#
if [ ${inxs} -eq 1 ];                      then CONFL="${CONFL}_NEXTSIM_OA3"; NSIA="NEXTSIM"; NMSIA="neXtSIM"; fi
if [ ${iagr} -eq 1 ];                      then CONFL="${CONFL}_NST"        ; fi
if [ ${isabl} -eq 1 ];                      then CONFL="${CONFL}_ABL"        ; fi


NEMOv_bak=${NEMOv} ; # NEMOv will be overwritten by what's in the setup...
NZ_bak=${NZ}
# Do we find a setup.bash file for this config into NCM ???
fsetup_conf=${NCM_DIR}/CONFS/${CONFL}/setup.bash
if [ -f ${fsetup_conf} ]; then
    echo
    echo "Found! ${fsetup_conf} !"
    . ${fsetup_conf}
    echo
else
    echo "Not found! ${fsetup_conf} !"
    exit
fi


NEMOv=${NEMOv_bak} ; # back to the value defined earlier in THIS script!
NZ=${NZ_bak} ; # back to the value defined earlier in THIS script!

ARCHB="${ARCH}" ; # `ARCHB` is the basis architecture !!!
if [ ${ioa3} -eq 1 ]; then ARCH+="_OA3"; fi


# B A T H Y   &   D O M A I N   T O   U S E :
FBATHY=""
FDMCFG="domain_cfg_L${NZ}_${NEMOv}.nc"; # set to "" if not relevant (like for NEMO beforfe v4!)

SIZE_RSTRT_DIR='XM' ; # size of 1 restart directory as specified with command "du -sh *"
list_freq_out="1h" ; # time-tag of files to save/archive

HERE=`pwd`

DIR_FATM_ROOT="${FATM_DIR}/${NM_ATM_FORC}"
echo; echo " *** DIR_FATM_ROOT = ${DIR_FATM_ROOT}"; echo

if [ ${inxs} -eq 1 ]; then
    echo
    if [ "${NEXTSIMDIR}" = "" ] || [ "${NEXTSIM_DATA_DIR}" = "" ] || [ "${NEXTSIM_MESH_DIR}" = "" ]; then
        echo "STOP!!! You must export NEXTSIMDIR, NEXTSIM_DATA_DIR & NEXTSIM_MESH_DIR for your architecture !!!"; exit
    fi
    if [ ! -d "${NEXTSIMDIR}" ] || [ ! -d "${NEXTSIM_DATA_DIR}" ] || [ ! -d "${NEXTSIM_MESH_DIR}" ]; then
        echo "STOP!!! At least one of these directories does not exist:"
        echo " ${NEXTSIMDIR}"; echo " ${NEXTSIM_DATA_DIR}"; echo " ${NEXTSIM_MESH_DIR}"
        exit
    fi
fi

POST_TRTMT="lb_nc3tonc4_visu.sh"
launch_post_trtmt=false

# ROOT Directory installed by nemo_conf_manager and in which NEMO should be compiled:
if [ "${NEMO_REPO_ROOT}" = "" ]; then echo "STOP!!! You must export a value for 'NEMO_REPO_ROOT' !!!"; exit; fi
NEMO_REPO_DIR=${NEMO_REPO_ROOT}/NEMOv${NEMOv}${CID}

# Trying to find the ARCH file:
ARCH_FILE=${NEMO_REPO_DIR}/${NM_DARCH}/arch-${ARCH}.fcm
echo ; echo " Archi file: ${ARCH_FILE}"; echo
check_on_file ${ARCH_FILE}

MPI_HOME=`cat  ${ARCH_FILE} | grep '^%MPI_HOME'  | sed -e "s|%MPI_HOME||g"  -e "s| ||g" | sed -e 's|${HOME}|/home/users/brodeau|g'`
NCDF_HOME=`cat ${ARCH_FILE} | grep '^%NCDF_HOME' | sed -e "s|%NCDF_HOME||g" -e "s| ||g" | sed -e 's|${HOME}|/home/users/brodeau|g'`
HDF5_HOME=`cat ${ARCH_FILE} | grep '^%HDF5_HOME' | sed -e "s|%HDF5_HOME||g" -e "s| ||g" | sed -e 's|${HOME}|/home/users/brodeau|g'`
XIOS_HOME=`cat ${ARCH_FILE} | grep '^%XIOS_HOME' | sed -e "s|%XIOS_HOME||g" -e "s| ||g" | sed -e 's|${HOME}|/home/users/brodeau|g'`
echo "XIOS_HOME=${XIOS_HOME}"
if [ ${ioa3} -eq 1 ]; then
    OASIS_HOME=`cat ${ARCH_FILE}| grep '^%OASIS_HOME'| sed -e "s|%OASIS_HOME||g" -e "s| ||g"| sed -e 's|${HOME}|/home/users/brodeau|g'`
    echo "OASIS_HOME=${OASIS_HOME}"
fi
echo

cdir=${NM_DCONF}
if [ ${itst} -eq 1 ]; then cdir="tests"; fi

NEM_EXE="${NEMO_REPO_DIR}/${cdir}/${CONFL}/BLD/bin/nemo.exe" ; # NEMO executable
if [ ${inxs} -eq 1 ]; then
    SIA_EXE="${NEXTSIMDIR}/model/bin/nextsim.exec"     ; # neXtSIM executable
fi
if [ ${isas} -eq 1 ]; then
    NEM_EXE="${NEMO_REPO_DIR}/${cdir}/${CONF}_OPA_OA3/BLD/bin/opa.exe"
    SIA_EXE="${NEMO_REPO_DIR}/${cdir}/${CONFL}/BLD/bin/sas.exe"
fi

echo "Executables to use ="
echo " -> ${NEM_EXE}"
if [ ${ioa3} -eq 1 ]; then echo " -> ${SIA_EXE}"; fi
echo

# Some defaults:
#NNODES=1 ; # number of nodes to use, "NNODES" is only used to control that the proc/node repartition chosen makes sense!
NX_NST=0; NY_NST=0
NXA=0 ; NYA=0
i_copy_forcing_to_scratch=0
NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
NCORES_SIA=0 ; NCORES_SIA_P_NODE=0
MMI="2048" ; # value for neXtSIM `-mat_mumps_icntl_23` option

if [ ${IDEBUG} -eq 1 ]; then
    #
    case ${ARCHB} in
        #
        "POMME")
            NCORES_NEM=4; NX=2 ; NY=2; NCORES_NEM_P_NODE=4
            NNODES_XIO=0 ; NCORES_XIO_P_NODE=1
            ;;
        #
        "MERLAT")
            NCORES_NEM=4; NX=2 ; NY=2; NCORES_NEM_P_NODE=4
            NNODES_XIO=0 ; NCORES_XIO_P_NODE=1
            ;;
        #
        "LUITEL")
            NCORES_NEM=4; NX=2 ; NY=2; NCORES_NEM_P_NODE=4
            NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
            ;;
        #
        "MEOMCAL1")
            NCORES_NEM=4; NX=2 ; NY=2; NCORES_NEM_P_NODE=4
            NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
            ;;
        #
        "ADASTRA")
            #//////////////////////  XIOS SERVER ! /////////////////////////////////////////////////////
            ## 1 Node:
            NNODES=1
            NCORES_NEM=178 ; NX=16 ; NY=15; NCORES_NEM_P_NODE=178
            NNODES_XIO=0 ;                  NCORES_XIO_P_NODE=10
            #///////////////////////////////////////////////////////////////////////////////////////
            #
            ;;
        "FRAM")
            #NNODES=1
            #NCORES_NEM=28; NX=4; NY=7; NCORES_NEM_P_NODE=28
            #NNODES_XIO=0 ; NCORES_XIO_P_NODE=4
            #
            NNODES=2
            #NCORES_NEM=60; NX=6; NY=10; NCORES_NEM_P_NODE=30
            #NCORES_NEM=58; NX=2; NY=29; NCORES_NEM_P_NODE=29
            NCORES_NEM=58; NX=13; NY=5; NCORES_NEM_P_NODE=29 ; # MPP
            NNODES_XIO=0 ;              NCORES_XIO_P_NODE=3
            #
            #NNODES=3
            #NCORES_NEM=90; NX=9; NY=10; NCORES_NEM_P_NODE=30
            #NNODES_XIO=0 ;              NCORES_XIO_P_NODE=2
            ;;
        #
        "JACKZILLA" )
            # 1 visu node
            NNODES=1
            #
            #Debug:
            #NCORES_NEM=2 ; NX=1 ; NY=2; NCORES_NEM_P_NODE=2
            #NNODES_XIO=0 ; NCORES_XIO_P_NODE=2
            #
            #NCORES_NEM=23 ; NX=5 ; NY=5; NCORES_NEM_P_NODE=23 ; # MPP, 2LP,  NANUK4
            #NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
            #
            # Good:
            #NCORES_NEM=29 ; NX=4 ; NY=8; NCORES_NEM_P_NODE=29 ; # MPP, 3LP, NANUK4
            #NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
            #
            #NCORES_NEM=32 ; NX=5 ; NY=7; NCORES_NEM_P_NODE=32 ; # MPP, 3LP, NANUK4
            #NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
            #
            NCORES_NEM=33 ; NX=4 ; NY=9; NCORES_NEM_P_NODE=33 ; # MPP, 3LP, NANUK4
            NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
            #
            ;;
        #
        "FRAZILO" )
            # 1 visu node
            NNODES=1
            #
            #Debug:
            #NCORES_NEM=2 ; NX=1 ; NY=2; NCORES_NEM_P_NODE=2
            #NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
            #
            #NCORES_NEM=23 ; NX=5 ; NY=5; NCORES_NEM_P_NODE=23 ; # MPP, 2LP, NANUK4
            #NNODES_XIO=0 ; NCORES_XIO_P_NODE=6
            #
            # Good:
            NCORES_NEM=29 ; NX=4 ; NY=8; NCORES_NEM_P_NODE=29 ; # MPP, 3LP, NANUK4
            NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
            #
          ;;
	  "JZ-SLX")
                echo "=========== JEAN ZAY RUN"
                #QUEUE_OPTION="--account=cli@cpu --qos=qos_cpu-dev --dependency=singleton --exclusive --hint=nomultithread"
                QUEUE_OPTION="--account=cli@cpu --dependency=singleton --exclusive --hint=nomultithread"
		#NNODES=1   already computed above
                #NCORES_NEM=38    # already computed above 
		NX=6 ; NY=7; 
		NCORES_NEM_P_NODE=$NPROCJZNODE #38 ; # already computed above MPP, 3LP, NANUK4
                NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
                ;;
 esac
    #
else
    #
    case ${ARCHB} in
        #
        "MEOMCAL1")
            NCORES_NEM=4 ; NX=2 ; NY=2; NCORES_NEM_P_NODE=4
            NX_NST=2; NY_NST=2
            NNODES_XIO=0 ; NCORES_XIO_P_NODE=0 ; # no server!
            ;;
        #
        "OCCIGEN")
            NCORES_NEM=48 ; NX=0 ; NY=0; NCORES_NEM_P_NODE=24
            NX_NST=0 ; NY_NST=0 ; # = 48
            NNODES_XIO=1 ; NCORES_XIO_P_NODE=5 ; #
            ;;
        "FRAM")
            NCORES_NEM=30; NX=5; NY=6; NCORES_NEM_P_NODE=30
            NNODES_XIO=0 ; NCORES_XIO_P_NODE=2
            ;;
        #
        "JACKZILLA" )
            # 1 visu node
            NNODES=1
            NCORES_NEM=30 ; NX=4 ; NY=8; NCORES_NEM_P_NODE=30 ; # MPP, 2LP,  NANUK12
            NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
            #            
            ;;
          "JZ-SLX")
                echo "=========== JEAN ZAY RUN"
                #QUEUE_OPTION="--account=cli@cpu --qos=qos_cpu-dev --dependency=singleton --exclusive --hint=nomultithread"
                QUEUE_OPTION="--account=cli@cpu --dependency=singleton --exclusive --hint=nomultithread"
                #NNODES=1   already computed above
                #NCORES_NEM=38    # already computed above 
                NX=6 ; NY=7;
                NCORES_NEM_P_NODE=$NPROCJZNODE #38 ; # already computed above MPP, 3LP, NANUK4
                NNODES_XIO=0 ; NCORES_XIO_P_NODE=0
                ;;
   esac
    #
fi
echo "==================== EH?"
echo $NCORES_NEM, $NCORES_NEM_P_NODE

JD=1  ; # current (cummulated) day since begining of simulation
JDy=1 ; # current day of year

SCRIPT_NAME=`basename $0`

echo

# Getting CONFCASE from the name of the script...
CONFCASE=`basename ${0} | sed -e s/'.sh'/''/g | sed -e s/'.job'/''/g`
NCONF=`echo ${CONFCASE} | cut --delimiter="-" -f 1,1`
CASE=`echo ${CONFCASE} | cut --delimiter="-" -f 2,2`
echo " CONFCASE = ${CONFCASE}"
echo " NCONF = ${NCONF}"
echo " CASE = ${CASE}" ; echo
if [ "${NCONF}" != "${CONFL}" ] && [ ${ioa3} -ne 1 ]; then echo "PROBLEM: ${NCONF} (name of script) should be equal to ${CONFL} (declared config) !"; exit; fi
echo
DATA_CONF_DIR=${DIR_STOR_READ_ROOT}/${CONF}/${CONF}.L${NZ}-I
if [ ! -d ${DATA_CONF_DIR} ]; then echo "ERROR: dir ${DATA_CONF_DIR} does not exist!!!"; exit; fi
echo " DATA_CONF_DIR => ${DATA_CONF_DIR} "; echo

SIA_IN_DIR="${DATA_CONF_DIR}/${NSIA}"
if [ ${ioa3} -eq 1 ]; then
    if  [ ! -d ${SIA_IN_DIR} ]; then echo "ERROR: dir ${SIA_IN_DIR} does not exist!!!"; exit; fi
    echo " SIA_IN_DIR => ${SIA_IN_DIR} "; echo
fi

if [ "${DIR_FATM_ROOT}" = "" ]; then
    DIR_FATM_ROOT="${DATA_CONF_DIR}/FATM"
fi
DIR_FATM_ITRP="${DATA_CONF_DIR}/FATM/${NM_ATM_FORC}" ; # atmo forcing interpolated on CONF !!!
i_interp_fatm_exists=0
if [ -d ${DIR_FATM_ITRP} ] && [ "`\ls ${DIR_FATM_ITRP}/*_y* 2>/dev/null`" != "" ]; then i_interp_fatm_exists=1; fi

##############################################################################
if (${LNENSRST} .eq. "true"); then
mkdir -p ${myRSTDIR}/${CONFCASE}
cd ${myRSTDIR}/${CONFCASE}

for K in $(seq -f "%03g" $MEMBER0 $MEMBERN); do
echo "*************** prepare restart files for member $K"
ln -sf ${myRSTDIR}${K}${perturbnam} ${myRSTDIR}${CONFCASE}/${K}${myRSTPREFIX}${myRSTIT}"_restart_ice.nc"
ln -sf  ${myRSTDIR}/${K}${myRSTPREFIX}${myRSTIT}"_restart_abl.nc" ${myRSTDIR}${CONFCASE}/${K}${myRSTPREFIX}${myRSTIT}"_restart_abl.nc"
ln -sf  ${myRSTDIR}/${K}${myRSTPREFIX}${myRSTIT}"_restart_oce.nc" ${myRSTDIR}${CONFCASE}/${K}${myRSTPREFIX}${myRSTIT}"_restart_oce.nc"
done
ln -sf  ${myRSTDIR}/${myRSTPREFIX}${myRSTIT}"_restart_oce.nc" ${myRSTDIR}${CONFCASE}/${myRSTPREFIX}${myRSTIT}"_restart_oce.nc"
ln -sf  ${myRSTDIR}/${myRSTPREFIX}${myRSTIT}"_restart_abl.nc" ${myRSTDIR}${CONFCASE}/${myRSTPREFIX}${myRSTIT}"_restart_abl.nc"
ln -sf ${myRSTDIR}${K}${perturbnam} ${myRSTDIR}${CONFCASE}/${myRSTPREFIX}${myRSTIT}"_restart_ice.nc"
fi

# Initializing a run from a given restart files:
#  ( not a natural restart from previous submission )
# ----------------------------------------------------------
init_from_rstrt=${myRSTIT}       ;  #1200 # set to something else than 0 if you want to use external
#                              # restart files, at time step "init_from_rstrt" and specify F_R_INI:
#
CASE_CLONE=""     ;   # if set and `init_from_rstrt` also set then will start the current job
#                           # cloning the state of `CASE_CLONE` at time step `init_from_rstrt`
#                           # `CASE_CLONE` is just another `CASE` of the same CONF !!!
#                           # => this means we make a copy of restarts and important log + 0_* files!
init_rstrt_m1=1         ;   # time step at which cloned exp started before spawning restart at `init_from_rstrt`
#                           # => so SAVEDIR of cloned exp is something like `init_rstrt_m1-init_from_rstrt`
#
#
l_respect_rstrt_time=true ; # if set to false and "init_from_rstrt =/ 0" then will treat the restart as
#                           # an initial state to start from and will ignore the date / time consistency
#                           # and will start the 1st of January !!!
cts_rsrt=`printf "%08d" ${init_from_rstrt}`
cts_rsrt_m1=`printf "%08d" ${init_rstrt_m1}`
#
F_R_INI=${myRSTDIR}${CONFCASE}/${myRSTPREFIX}${myRSTIT}
#F_R_INI="/lustre/fsn1/projects/rech/cli/regi915/NEMO/NANUK4/NANUK4_ICE_ABL-EABLBBM102-R/00002040/NANUK4_ICE_ABL-EABLBBM102_00002040"
# Directory containing the atmospheric forcing:
FATM_S_DIR="FATM"  ; # sub-dir of ${DATA_CONF_DIR} containing forcing...
FATM_REF_DIR="${DIR_FATM_ROOT}"
FATM_SCR_DIR=""    ; # containing exactly the same as above but on the scratch dir! For performance! Leave blank otherwize...
##############################################################################


if [ ${init_ice} -gt 0 ] && [ ${init_from_rstrt} -gt 0 ]; then
    echo; echo "Mhhh! Problem: we have init_ice=${init_ice} & init_from_rstrt=${init_from_rstrt} !"
    exit
fi

XIO_EXE="${XIOS_HOME}/bin/xios_server.exe" ; # XIOS executable
echo " XIO_EXE => ${XIO_EXE}"

echo; echo "About to launch run ${CONFCASE} forced."; echo; echo

TMPDIR=${DIR_STOR_WRIT_ROOT}/tmp/${CONF}/${CONFCASE}_prod ; mkdir -p ${TMPDIR}
RSTDIR=${DIR_STOR_SAVE_ROOT}/${CONF}/${CONFCASE}-R        ; mkdir -p ${RSTDIR}
SAVDIR=${DIR_STOR_SAVE_ROOT}/${CONF}/${CONFCASE}-S        ; mkdir -p ${SAVDIR}
RSTDIR_OA3=${RSTDIR}
if [ ${inxs} -eq 1 ]; then
    RSTDIR_NXS=${RSTDIR}/nextsim ; mkdir -p ${RSTDIR_NXS}/out
    SAVDIR_NXS=${SAVDIR}/nextsim ; mkdir -p ${SAVDIR_NXS}
    RSTDIR_OA3=${RSTDIR}/oasis   ; mkdir -p ${RSTDIR_OA3}
    RSTDIR=${RSTDIR}/opa         ; mkdir -p ${RSTDIR}
    SAVDIR=${SAVDIR}/opa         ; mkdir -p ${SAVDIR}
    cd ${SAVDIR_NXS}; ln -sf ${RSTDIR_NXS}/out ./restart
    if [ -z ${NCORES_SIA} ]; then echo "ERROR: NCORES_SIA the number of cores for ${NMSIA} must be set!"; exit; fi
fi

if [ ${iagr} -eq 1 ]; then
    cd ${TMPDIR}
    if [ ! -L 1_restarts ]; then ln -sf ${RSTDIR} 1_restarts ; fi
fi

echo; echo
echo " *** Production dir       => ${TMPDIR}"
echo " *** Output archiving dir => ${SAVDIR}"
echo " *** Output archiving dir => ${RSTDIR}"
echo

cd ${HERE}/

LOLO=0  # zero is false
if (( LOLO == 1 )); then
# CORE / NODE / EXEC DECOMPOSITION
##################################
if [ ${NBCPN} -le 0 ]; then
    echo " ERROR: please set NBCPN (nb of cores per node) for host ${ARCHB}"
    echo "        => in file ${NCM_DIR}/CONFS/HOSTS.bash"
    exit
fi

if [ -z ${NCORES_NEM} ] || [ -z ${NCORES_NEM_P_NODE} ] || [ -z ${NX} ] || [ -z ${NY} ] \
       || [ ${NCORES_NEM} -le 0 ] || [ ${NCORES_NEM_P_NODE} -le 0 ] || [ ${NX} -le 0 ] || [ ${NY} -le 0 ]; then
    echo " PROBLEM: NCORES_NEM, NCORES_NEM_P_NODE, NX, NY => ${NCORES_NEM}, ${NCORES_NEM_P_NODE}, ${NX}, ${NY}"; exit
fi
if [ $((NX*NY)) -ne ${NCORES_NEM} ]; then
    echo; echo "WARNING: NX*NY /= NCORES_NEM !!!"; echo "  => probably removing land procs ???" ; echo
fi

NIDLE_GCM_CORES=0                                           ; # number of idle GCM cores in total (not per node!)
NCORES_GCM=$(( NCORES_NEM + NCORES_SIA ))           ; # number of cores dedicated to GCM (NEMO or neXtSIM, not XIOS!)
NCORES_TOT=${NCORES_GCM}                            ; # First guess
NNODES_TOT=$(( NCORES_TOT/NBCPN + NNODES_XIO + 1 )) ; # First guess of number of nodes to book based
#                                                     # only on number of GCM cores (and potentially the number of xios nodes)
if [ ${NNODES_XIO} -eq 0 ]; then
    # XIOS processes are mixed with that of GCMs
    if [ ${NCORES_XIO_P_NODE} -ge 0 ]; then
        NCORES_XIO=$(( NNODES_TOT*NCORES_XIO_P_NODE ))
        NCORES_TOT=$(( NCORES_GCM + NCORES_XIO ))
        # Update number of nodes to book:
        NNODES_TOT=$(( NCORES_TOT/NBCPN ))
        if [ $((NCORES_TOT%NBCPN)) -ne 0 ]; then NNODES_TOT=$(( NNODES_TOT + 1 )); fi
        NNODES_GCM=${NNODES_TOT}
        #
        NCORES_XIO=$(( NNODES_TOT*NCORES_XIO_P_NODE )) ; # need to update it with new NNODES_TOT!
        NCORES_TOT=$(( NCORES_GCM + NCORES_XIO ))      ; #   "          "
        NIDLE_GCM_CORES=$(( NNODES_TOT*NBCPN - NCORES_GCM - NCORES_XIO ))
        cbla1=" with some"
        cbla2="($((NIDLE_GCM_CORES/NNODES_TOT)) on each node)"
    else
        echo " NCORES_XIO_P_NODE cannot be < 0 !!!"; exit
    fi
    #
elif [ ${NNODES_XIO} -ge 1 ]; then
    # XIOS processes are only used on nodes fully dedicated to XIOS!
    if [ ${NCORES_XIO_P_NODE} -ge 1 ]; then
        NNODES_GCM=$(( NCORES_GCM/NBCPN + 1 ))
        NCORES_XIO=$(( NNODES_XIO*NCORES_XIO_P_NODE ))
        NCORES_TOT=$(( NCORES_GCM + NCORES_XIO ))
        NNODES_TOT=$(( NNODES_GCM + NNODES_XIO ))
        NIDLE_GCM_CORES=$(( NNODES_GCM*NBCPN - NCORES_GCM ))
        cbla1=" fully dedicated to"
        cbla2="over the ${NNODES_GCM} GCM-dedicated nodes ($((NIDLE_GCM_CORES/NNODES_GCM)) on each of these GCM nodes)"
    else
        echo " NCORES_XIO_P_NODE cannot be < 1 if NNODES_XIO>0 !!!"; exit
    fi
else
    echo " NNODES_XIO cannot be < 0 !!!"; exit
fi

if [ ${NNODES_TOT} -ne ${NNODES} ]; then
    echo
    echo "PROBLEM: something is wrong about the nodes/cores decomposition you have chosen"
    echo " ==> you were expecting ${NNODES} nodes (NNODES)"
    echo " ==> we calculated ${NNODES_TOT} nodes (NNODES_TOT)"
    if [ ${NNODES} -gt ${NNODES_TOT} ] && [ ${NNODES_XIO} -eq 0 ]; then
        echo " ===> do you want to force NNODES_TOT to ${NNODES}?"
        read -r -p "   ??? [y/N] " response
        case ${response} in
            [oO]|[sS]|[yY])
                NNODES_GCM=$((NNODES_GCM + NNODES - NNODES_TOT))
                NNODES_TOT=${NNODES}
                NCORES_XIO=$(( NNODES_TOT*NCORES_XIO_P_NODE )) ; # need to update it with new NNODES_TOT!
                NCORES_TOT=$(( NCORES_GCM + NCORES_XIO ))      ; #   "          "
                NIDLE_GCM_CORES=$(( NNODES_TOT*NBCPN - NCORES_GCM - NCORES_XIO ))
                cbla2="over the ${NNODES_GCM} GCM-dedicated nodes ($((NIDLE_GCM_CORES/NNODES_GCM)) on each of these GCM nodes)"
                ;;
            *) exit
                ;;
        esac
    else
        exit
    fi
fi

if [ $(( NCORES_GCM/NNODES_GCM )) -ne $((NCORES_NEM_P_NODE + NCORES_SIA_P_NODE)) ]; then
    echo "PROBLEM: NCORES_GCM/NNODES_GCM /= NCORES_NEM_P_NODE !!!"
    echo " $(( NCORES_GCM/NNODES_GCM )) , ${NCORES_NEM_P_NODE}"
    echo; exit
fi

# In the end how many active processes per node ???
NPPN1=$((NCORES_TOT/NNODES_TOT))
NPPN2=$((NCORES_NEM_P_NODE + NCORES_XIO_P_NODE + NCORES_SIA_P_NODE))
if [ ${NPPN1} -ne ${NPPN2} ]; then
    echo "PROBLEM: estimation of # of active processes per node!:"
    echo "  => NCORES_TOT, NNODES_TOT = ${NCORES_TOT}, ${NNODES_TOT}"
    echo "  => NCORES_TOT/NNODES_TOT = ${NPPN1}"
    echo "  => NCORES_NEM_P_NODE + NCORES_XIO_P_NODE + NCORES_SIA_P_NODE = ${NPPN2}"
    echo; exit
fi
NPPN=${NPPN1}

#NNODES_GCM=$((${NNODES_GCM}>1?${NNODES_GCM}:1)); # at least 1!!!

# Number of idle cores on each GCM node?
NICPN=0
if [ ${NIDLE_GCM_CORES} -gt 0 ]; then NICPN=$((NIDLE_GCM_CORES / NNODES_GCM)); fi

echo " We are going to book ${NNODES_TOT} nodes ($((NNODES_TOT*NBCPN)) cores) and use ${NCORES_TOT} cores!"
echo "   => ${NIDLE_GCM_CORES} idle cores in total ${cbla2}"
cnx=`printf "%02d" ${NX}` ; cny=`printf "%02d" ${NY}`
echo "   NEMO => ${NNODES_GCM} nodes (${NCORES_NEM} cores => ${cnx}x${cny})"
echo "        => ${NCORES_NEM_P_NODE} NEMO processes on each node${cbla1} NEMO!"
if [ ${inxs} -eq 1 ]; then
    echo " neXtSIM => ${NNODES_GCM} nodes (${NCORES_SIA} cores"
    echo "         => ${NCORES_SIA_P_NODE} processes on each node${cbla1}!"
fi
if [ ${isas_cpl} -eq 1 ]; then
    if [ ${NXA} -eq 0 ] || [ ${NYA} -eq 0 ]; then "ERROR: give NXA and NYA for SAS!!!"; exit; fi
    cnx=`printf "%02d" ${NXA}` ; cny=`printf "%02d" ${NYA}`
    echo "    SAS => ${NNODES_GCM} nodes (${NCORES_SIA} cores => ${cnx}x${cny})"
    echo "        => ${NCORES_SIA_P_NODE} processes on each node${cbla1}!"
fi
echo "   XIOS => ${NNODES_XIO} nodes (${NCORES_XIO} cores)"
if [ ${NNODES_XIO} -gt 0 ]; then
    echo "        => ${NCORES_XIO_P_NODE} XIOS processes on each node${cbla1} XIOS!"
else
    echo "        => ${NCORES_XIO} XIOS processes spread on the same node(s) as NEMO..."
fi
echo " *** number of idle cores on each GCM node = ${NICPN}"; echo

else
  # so far does not take into account any cores for xios
  NNODES_TOT=${NNODES}
  NCORES_TOT=${NCORES_NEM}
  NPPN=${NPROCJZNODE} 
fi # end if LOLO 


RSTRT="false"; IRCTL=2; TSD_INIT="true"; # default, do not touch

JY=`expr ${Y1} + 0`
nbdy=`nb_day_in_year ${JY}`

if [ ${ioa3} -eq 1 ]; then
    if [ $(( DT % DT_SIA )) -ne 0 ]; then
        echo " PROBLEM: OPA time step (${DT}) is not a multiple of ${NMSIA} time step (${DT_SIA}) !!!"; exit
    fi
    DT_CPL=${DT}
    echo
    echo " ***  OPA     time step = ${DT}"
    echo " ***  ${NMSIA} time step = ${DT_SIA}"
    echo " *** coupling time step = ${DT_CPL}"
    echo
fi

CM1=`printf "%02d" ${M1}`
SDATE0="${Y1}${CM1}01" ; # First guess...
SDATE=${SDATE0} ; # First guess...
NDAYS_EXP=`fnb_days ${LENGTH_SEG} ${SDATE}`
nbd_brs=`fnb_days ${RESTRT_FRQ} ${SDATE}`

NLJOB=$(((3600*24*NDAYS_EXP)/DT))
rr=$(((3600*24*NDAYS_EXP)%DT))
if [ ${rr} -ne 0 ]; then echo " (3600*24*NDAYS_EXP)%DT  = ${rr} !!!! (year = ${JY})"; exit; fi
NSTOCK=$(((3600*24*nbd_brs)/DT))
echo; echo "NSTOCK, NLJOB = ${NSTOCK}, ${NLJOB} (year = ${JY})"; echo
if [ ${iagr} -eq 1 ]; then NLJOB_n=$(((3600*24*NDAYS_EXP)/DT_n)); NSTOCK_n=$(((3600*24*nbd_brs)/DT_n)); fi

# How many time steps in 1 day and 1 year:
NDT1D=$(((24*3600)/DT)) ; echo " => ${NDT1D} time steps per day"
NDT1Y=$((nbdy*24*3600/DT)) ; echo " => ${NDT1Y} time steps per year"

JOB_SEGMENT_DAYS=$((NLJOB/NDT1D))


# About restart frequency
# -----------------------
FREQ_RST_Y=$((${NLJOB}/${NDT1Y}))      ; # Frequency of restart file in years
FREQ_RST_D=$((${nbdy}*${NLJOB}/${NDT1Y}))  ; # Frequency of restart file in days
FREQ_DUMP_RST_D=$((${nbdy}*${NSTOCK}/${NDT1Y}))  ; # Frequency of spawning a restart
# if the restart freq is less than 1 year:
if [ ${FREQ_RST_Y} -eq 0 ]; then
    echo " => Job will complete ${FREQ_RST_D} day(s)"
    echo " ==> and will spawn a restart every ${FREQ_DUMP_RST_D} day(s)"
    frstd_tmp=$((${FREQ_RST_D}>1?${FREQ_RST_D}:1)) ; # max(${FREQ_RST_D}:1)
    if [ ! $((${nbdy}%${frstd_tmp})) -eq 0 ]; then echo;echo "WARNING: ${nbdy} is not a multiple of ${FREQ_RST_D} !!!"; sleep 1;echo; fi
    JYend=${JY}
    DoYini=`MMDD_to_day_year ${CM1}01 ${JY}`
    SDATE=`printf "%04d" ${JY}``day_year_to_MMDD ${DoYini} ${JY}`
    EDATE=`printf "%04d" ${JY}``day_year_to_MMDD ${frstd_tmp} ${JY}`
else
    echo " => Job will complete ${FREQ_RST_Y} year(s) (every ${FREQ_RST_D} days)"
    JYend=$((${JY}+${FREQ_RST_Y}-1))
    SDATE=`printf "%04d" ${JY}`${CM1}01
    EDATE=`printf "%04d" ${JYend}`1231
fi

jsub=1       # number of the job submission that's gonna be launched
irstrt=0
icpt=0

if [ ${init_from_rstrt} -eq 0 ]; then
    l_respect_rstrt_time=true ; # we overide any possible value when init_from_rstrt=0
fi

if [ ${init_from_rstrt} -gt 0 ] && [ "${CASE_CLONE}" != "" ]; then

    echo ; echo "###################################################################"
    echo; echo "Initial EXP cloning!"
    echo " => EXP ${CASE} shall start at cloned time state ${init_from_rstrt} of EXP ${CASE_CLONE}!"

    if [ ! ${init_rstrt_m1} -ge 1 ]; then echo "PROVIDE a descent init_rstrt_m1 !!!"; exit; fi

    # 1/ Creating a copy of the restart dir
    # =====================================
    SAVDIR_CLONE=`echo "${SAVDIR}" | sed -e "s|${CASE}|${CASE_CLONE}|g"`/${cts_rsrt_m1}-${cts_rsrt}/logs
    echo " *** dir to clone production logs from:"; echo "  ==> ${SAVDIR_CLONE}"
    if [ ! -d ${SAVDIR_CLONE} ]; then echo "PROBLEM: ${SAVDIR_CLONE} does not exist!!!"; exit; fi
    #
    echo; echo " 1/ Restart directory ${cts_rsrt} cloning"; echo
    RSTDIR_CLONE=`echo "${RSTDIR}" | sed -e "s|${CASE}|${CASE_CLONE}|g"`
    echo " *** dir to clone restarts from:": echo "  ==> ${RSTDIR_CLONE}"
    cdcl="${RSTDIR_CLONE}/${cts_rsrt}"
    echo " ===> ${cdcl}"
    if [ ! -d ${cdcl} ]; then echo "PROBLEM: ${cdcl} does not exist!!!"; exit; fi
    #
    cd ${RSTDIR}/
    i0=0 ; ic=0
    i0=`\ls ${cts_rsrt}/*${CASE}*.nc       2>/dev/null | wc -w`
    ic=`\ls ${cts_rsrt}/*${CASE_CLONE}*.nc 2>/dev/null | wc -w`
    if [ ${i0} -eq 0 ] && [ ${ic} -eq 0 ]; then
        echo "Need to import!"
        ${CP} ${cdcl} .   ; # making a copy
    else
        echo "No need to import them!"
    fi
    i0=`\ls ${cts_rsrt}/*${CASE}*.nc       2>/dev/null | wc -w`
    ic=`\ls ${cts_rsrt}/*${CASE_CLONE}*.nc 2>/dev/null | wc -w`
    if [ ${ic} -gt 0 ] && [ ${i0} -lt ${ic} ]; then
        echo "Need to rename them!"
        cd ${cts_rsrt}/
        list=`\ls *${CASE_CLONE}*.nc`
        for ff in ${list}; do
            fn=`echo ${ff} | sed -e "s|${CASE_CLONE}|${CASE}|g"`
            echo " mv ${ff} ${fn}"; mv -f ${ff} ${fn}
        done
    else
        echo "No need to rename them!"
    fi
    #
    # Now about neXtSIM and OASIS:
    if [ ${ioa3} -eq 1 ]; then
        cd ../
        # OASIS:
        RSTDIR_OA3_CLONE=`echo "${RSTDIR_OA3}" | sed -e "s|${CASE}|${CASE_CLONE}|g"`
        cdcl="${RSTDIR_OA3_CLONE}/${cts_rsrt}"
        if [ ! -d ${cdcl} ]; then echo "PROBLEM: ${cdcl} does not exist!!!"; exit; fi
        mkdir -p ${RSTDIR_OA3}/${cts_rsrt}
        ${CP} ${cdcl}/*.nc ${RSTDIR_OA3}/${cts_rsrt}/ 2>/dev/null
    fi
    #
    if [ ${inxs} -eq 1 ]; then
        # neXtSIM:
        RSTDIR_NXS_CLONE=`echo "${RSTDIR_NXS}" | sed -e "s|${CASE}|${CASE_CLONE}|g"`
        if [ ! -d ${RSTDIR_NXS_CLONE}/out ]; then echo "PROBLEM: ${RSTDIR_NXS_CLONE}/out does not exist!!!"; exit; fi
        # We need the date:
        ff="${SAVDIR_CLONE}/0_last_success_date.info"
        check_on_file ${ff}
        dtg_last=`cat ${SAVDIR_CLONE}/0_last_success_date.info` ; d_start=`dtg_itt ${dtg_last}`
        echo "  *** last day done by simulation to clone from: ${dtg_last} => so neXtSIM restarts -> ${d_start}"
        for cc in "field" "mesh"; do
            for ce in "bin" "dat"; do
                ${CP} ${RSTDIR_NXS_CLONE}/out/${cc}_${d_start}T000000Z.${ce} ${RSTDIR_NXS}/out/
                ${CP} ${RSTDIR_NXS_CLONE}/out/${cc}_${d_start}T000000Z.${ce} ${RSTDIR_NXS}/out/${cc}_final.${ce}
            done
        done
    fi
    echo

    # 2/ Creating the production directory with faked remains of exp
    # ==============================================================
    echo; echo " 1/ Creating the production directory with faked remains of exp"; echo
    #
    for cc in "jsub" "icpt" "date" "nljb" "iseg"; do
        check_on_file ${SAVDIR_CLONE}/0_last_success_${cc}.info
        ${CP} ${SAVDIR_CLONE}/0_last_success_${cc}.info ${TMPDIR}/
    done


    list="time.step ocean.output "
    if [ ${iagr} -eq 1 ]; then list+=" 1_time.step 1_ocean.output"; fi

    echo ${list}
    for ff in ${list}; do
        check_on_file ${SAVDIR_CLONE}/${ff}
        ${CP} ${SAVDIR_CLONE}/${ff} ${TMPDIR}/
    done
    echo ; echo "###################################################################"
    echo; echo

fi ; # if [ ${init_from_rstrt} -gt 0 ] && [ "${CASE_CLONE}" != "" ]

subdir_nl="Namelists"
if [ ${ioa3} -eq 1 ]; then subdir_nl="${subdir_nl}/opa"; fi




#  ###############################
#  L O O P   A L O N G   Y E A R S
#  ###############################

JYM1=${JY}
jsubm1=0
jsub=1
irstrt=0
icpt=0

while [ ${JY} -le ${Y2} ]; do

    echo
    #lb_wait ${CASE}
    echo

    echo "========================================================="
    ileap=`lb_is_leap ${JY}`
    if [ ${ileap} -eq 1 ]; then
        echo "*** Year ${JY} is a leap year!"
    else
        echo "*** Year ${JY} is NOT a leap year!"
    fi
    echo "========================================================="
    echo

    if [ -f ${TMPDIR}/time.step ]; then

        echo; echo "Alright, alright, alright!"; echo "  ==> We found a ${TMPDIR}/time.step !"; echo

        # If AGRIF should find a 1_time.step:
        if [ ${iagr} -eq 1 ]; then
            check_on_file ${TMPDIR}/1_time.step
            it1=`cat ${TMPDIR}/time.step` ; it2=`cat ${TMPDIR}/1_time.step`
            if [ $((it2/it1)) -ne ${NST_RAT} ] || [ $((it2%it1)) -ne 0 ]; then
                echo "Mhhh, something wrong about mother/child last time step values in time.step / 1_time.step !"; exit
            fi
        fi

        # Abort if the ocean.output looks suspicious:
        #na=`cat ${TMPDIR}/ocean.output | grep AAAAAAAA | wc -l`
        if [ -f "${PD}/001ocean.output" ]; then
        # If 001ocean.output exists, count occurrences of AAAAAAAA in it
        na=$(grep -c "AAAAAAAA" "${PD}/001ocean.output" 2>/dev/null)
        elif [ -f "${PD}/ocean.output" ]; then
        # If 001ocean.output doesn't exist, fall back to ocean.output
        na=$(grep -c "AAAAAAAA" "${PD}/ocean.output" 2>/dev/null)
        else
        # If neither file exists, set na to 0
        na=0
        fi
	
	if [ ${na} -eq ${naaa} ]; then
            echo " ocean.output looks OK! " ; echo
        else
            echo "PROBLEM: the last ocean.output looks suspicious! (couldn't see the 4 'AAAAAAAA' rows"
            echo "ABORTING!!! (${TMPDIR}/ocean.output) / na = ${na}" ; echo
            exit
        fi
        # Abort if we find the proof of an borted run:
        ee=`\ls ${TMPDIR}/*output.abort_* 2>/dev/null`
        if [ ! "${ee}" = "" ]; then
            echo "PROBLEM: found some *output.abort_* files in ${TMPDIR}!!!"
            echo "ABORTING!!!"; echo
            exit
        fi
        #
        for ffi in "jsub" "icpt" "date" "nljb" "iseg"; do
            check_on_file ${TMPDIR}/0_last_success_${ffi}.info
        done
        jsubm1=`cat ${TMPDIR}/0_last_success_jsub.info`
        jsub=$((jsubm1+1))
        icpt=`cat ${TMPDIR}/0_last_success_icpt.info`
        echo " *** From former go (sub #${jsubm1}) we get: jsub = ${jsub} | icpt = ${icpt} !"
        DATE_b=`cat ${TMPDIR}/0_last_success_date.info | sed -e "s/ //g"`
        echo "Date at the end of last go is: ${DATE_b}"
        # Ok, we're not completely screwed up and we stopped at the end of the day, so next day is
        SDATE=`dtg_itt ${DATE_b}`
        echo " => so next start at ${SDATE} !"
        #
        JY=`echo ${SDATE} | cut -c1-4` ; # changing current year accordingly
        irstrt=1
        init_from_rstrt=0
        l_respect_rstrt_time=true

    else
        # => no "time.step" found !!!
        irstrt=0
        if [ ${init_from_rstrt} -gt 0 ]; then
            CN_RST_DIR_IN=`dirname ${F_R_INI}`
            fbr=`basename ${F_R_INI}`
            if [ -d ${CN_RST_DIR_IN} ]; then
                echo "INITIAL CONDITION: Using restart files found into ${CN_RST_DIR_IN} !"
            else
                echo "PROBLEM: initial restart directory not found ! (${CN_RST_DIR_IN})"; exit
            fi

            CN_OCERST_IN=${fbr}_restart_oce
            CN_ICERST_IN=${fbr}_restart_ice
            CN_ABLRST_IN=${fbr}_restart_abl
            CN_STORST_IN=${fbr}_restart_sto

	    CN_SASRST_IN=${CN_OCERST_IN} ; # all that found into `restart_sas` are also in `restart_oce`, and the important ones such as VVL-related are also in `restart_oce` !

            list_rest_o=`ls                            ${CN_RST_DIR_IN}/${CN_OCERST_IN}*.nc`
            if [ ${isi3} -eq 1 ]; then list_rest_i=`ls ${CN_RST_DIR_IN}/${CN_ICERST_IN}*.nc`; fi
            list_rest_s="xxx"
            if [ ${isas_cpl} -eq 1 ]; then list_rest_s=`ls ${CN_RST_DIR_IN}/${CN_SASRST_IN}*.nc`; fi
            if [ "${list_rest_o}" = "" ] || [ "${list_rest_i}" = "" ] || [ "${list_rest_s}" = "" ]; then
                echo "PROBLEM: Some restarts are missing!!!"; exit
            fi

            if ${l_respect_rstrt_time}; then
                # Getting date in restart
                ftst=${CN_RST_DIR_IN}/${CN_OCERST_IN}_0000.nc
                if [ ! -f ${ftst} ]; then
                    ftst=${CN_RST_DIR_IN}/${CN_OCERST_IN}.nc
                    #if [ ! -f ${ftst} ]; then
                        #echo "PROBLEM: found neither ${CN_OCERST_IN}_0000.nc nor ${CN_OCERST_IN}.nc into ${CN_RST_DIR_IN}/ !"; exit
                    #fi
                fi
                kt=`ncdump -v kt ${ftst} | grep 'kt = ' | cut -d "=" -f2 | sed -e s/' '/''/g -e s/';'/''/g`
                SDATEm1=`ncdump -v ndastp ${ftst} | grep 'ndastp = ' | cut -d "=" -f2 | sed -e s/' '/''/g -e s/';'/''/g`
                JY=`echo ${SDATEm1} | cut -c1-4`
                cmd=`echo ${SDATEm1} | cut -c5-8`
                JYend=${JY}
                echo " => restart_oce says last day done was ${SDATEm1} and kt=${kt} !"
                JDYm1=`MMDD_to_day_year ${cmd} ${JY}`
                echo " => it was day # ${JDYm1} of ${JY}"
                nd=`nb_day_in_year ${JY}`
                if [ ${cmd} -eq 1231 ]; then
                    JY=$((JY+1)) ; JYend=${JY} ; nbdy=`nb_day_in_year ${JY}`
                    JDy=1
                    FREQ_RST_D=$((${nbdy}*${NLJOB}/${NDT1Y}))  ; # Frequency of restart file in days
                else
                    JDy=$((${JDYm1}+1))
                fi
                JDyend=$((JDy+FREQ_RST_D-1))
                if [ ${FREQ_RST_D} -eq 365 ] || [ ${FREQ_RST_D} -eq 366 ]; then
                    JDyend=$((${JDyend}<${FREQ_RST_D}?${JDyend}:${FREQ_RST_D})) ; # We force stop at the end of year we have started:
                fi
                SDATE="${JY}`day_year_to_MMDD $((${JDy}>1?${JDy}:1)) ${JY}`"
                echo " => so will start at day # ${JDy} of year ${JY}: ${SDATE}"
                yend=$((JY+(JDyend/nbdy)))
                dend=$((JDyend%nbdy))
                EDATE=`printf "%04d" ${yend}``day_year_to_MMDD ${dend} ${yend}`
                echo " => and stop at day # ${dend} of year ${yend}: ${EDATE}"
                # test this SDATE is consistent with date read into restart:
                sdt="${JY}`day_year_to_MMDD $((${JDYm1}>1?${JDYm1}:1)) ${JY}`"
                #if [ ! "${sdt}" = "${SDATEm1}" ]; then echo "PROBLEM: dates deduced from restart are fucked up!"; exit; fi
                echo "  ==> JDy, SDATE, EDATE deduced from restart => ${JDy}, ${SDATE}, ${EDATE} !"
                echo
            fi ; # if ${l_respect_rstrt_time}
            RSTRT="true"
            TSD_INIT="false"
        fi ; # if [ ${init_from_rstrt} -gt 0 ]

    fi ; # if [ -f ${TMPDIR}/time.step ]
    echo

    nbdy=`nb_day_in_year ${JY}`
    cmnth=`echo ${SDATE} | cut -c5-6`
    imnth=`expr ${cmnth} + 0` ; # current month

    NDAYS_EXP=`fnb_days ${LENGTH_SEG} ${SDATE}`
    nbd_brs=`fnb_days ${RESTRT_FRQ} ${SDATE}`

    #### PROBLEM: doublon with computation of `EDATE` earlier!!! Which can be removed ???? #######################
    # End of the comming run:
    sd=`echo ${SDATE} | cut -c5-8` ;  sd=`MMDD_to_day_year ${sd} ${JY}`
    jde=$((sd+NDAYS_EXP-1))
    if [ ${NDAYS_EXP} -eq 365 ] || [ ${NDAYS_EXP} -eq 366 ]; then
        jde=$((${jde}<${NDAYS_EXP}?${jde}:${NDAYS_EXP})) ; # We force stop at the end of year we have started:
    fi

    JYe=${JY}
    if [ ${jde} -gt ${nbdy} ]; then
        JYe=$((JY+1))
        jde=$((jde-nbdy))
    fi
    EDATE="${JYe}`day_year_to_MMDD ${jde} ${JYe}`"
    #############################################################################################################

    echo
    echo " *** Current month => ${imnth} !"
    echo " *** NDAYS_EXP=${NDAYS_EXP} !"
    echo " *** nbd_brs=${nbd_brs} !"
    echo " *** SDATE = ${SDATE} !"
    echo " *** EDATE = ${EDATE} !"
    echo    
    if [ "${CID}" != "" ]; then echo " *** ID of the code used => ${CID} "; fi
    echo
    sleep 3

    NLJOB=$(((3600*24*NDAYS_EXP)/DT)) ; # 1 year of simulation
    rr=$(((3600*24*NDAYS_EXP)%DT))
    if [ ${rr} -ne 0 ]; then echo " (3600*24*NDAYS_EXP)%DT  = ${rr} !!!! (year = ${JY})"; exit; fi
    NSTOCK=$(((3600*24*nbd_brs)/DT))
    echo; echo "NSTOCK, NLJOB = ${NSTOCK}, ${NLJOB} (year = ${JY})"; echo
    if [ ${iagr} -eq 1 ]; then NLJOB_n=$(((3600*24*NDAYS_EXP)/DT_n)); NSTOCK_n=$(((3600*24*nbd_brs)/DT_n)); fi

    ## Updating 'nn_fsbc':
    if [ ${force_fsbc} -lt 1 ]; then
        NFSBC=$(((3600*FRQ_EC)/DT))
        rr=$(((3600*FRQ_EC)%DT))
        echo " (3600*FRQ_EC)/DT = ${NFSBC}"
        if [ ${rr} -ne 0 ]; then echo " (3600*FRQ_EC)%DT = ${rr} !!!!"; exit; fi
    else
        NFSBC=${force_fsbc}
    fi

    # Re-submission:
    if [ ${irstrt} -eq 1 ]; then
        #
        citend=`printf "%08d" ${icpt}`
        # Restart official location:
        CN_RST_DIR_IN=${RSTDIR}/${citend}
        CN_OCERST_IN=${CONFCASE}_${citend}_restart_oce
        CN_ICERST_IN=${CONFCASE}_${citend}_restart_ice
        CN_ABLRST_IN=${CONFCASE}_${citend}_restart_abl
	CN_SASRST_IN=${CN_OCERST_IN}
        rm -f restart_*.nc
        fto=${CN_RST_DIR_IN}/${CN_OCERST_IN}
        fti=${CN_RST_DIR_IN}/${CN_ICERST_IN}
        fta=${CN_RST_DIR_IN}/${CN_ABLRST_IN}
        ftsto=${CN_RST_DIR_IN}/${CN_STORST_IN}
       	fts=${CN_RST_DIR_IN}/${CN_SASRST_IN}
        i_happy_with_restart=0
        #
        if [ ${i_skip_link_restarts} -eq 1 ]; then
            echo " *** skipping linking of restarts because i_skip_link_restarts=${i_skip_link_restarts} !!!"
            i_happy_with_restart=1
        fi
        #
        while [ ${i_happy_with_restart} -eq 0 ]; do
            if [ -f ${fto}_0000.nc ] || [ -f ${fto}.nc ]; then
                echo "Ocean restart files are into ${CN_RST_DIR_IN}, good!"; echo
                i_happy_with_restart=1
                if [ ${isi3} -eq 1 ]; then
                    if ! ([ -f ${fti}_0000.nc ] || [ -f ${fti}.nc ]); then
                        echo "But ice restart files are no there... Giving up!"; exit
                    fi
                fi
                if [ ${isas_cpl} -eq 1 ]; then
                    if ! ([ -f ${fts}_0000.nc ] || [ -f ${fts}.nc ]); then
                        echo "But ice restart files are no there... Giving up!"; exit
                    fi
                fi
                cd ${TMPDIR}/
                echo
            else
                echo "Restart files are not into ${CN_RST_DIR_IN}/ !"
                if [ -f ${TMPDIR}/`basename ${fto}_0000.nc` ]; then
                    echo " => but they actually are into ${TMPDIR}/ !"
                    echo "    => moving them into ${CN_RST_DIR_IN}/ !"
                    mkdir -p ${CN_RST_DIR_IN}
                    mv                            ${TMPDIR}/*${CN_OCERST_IN}*.nc ${CN_RST_DIR_IN}/
                    if [ ${isi3} -eq 1 ]; then mv ${TMPDIR}/*${CN_ICERST_IN}*.nc ${CN_RST_DIR_IN}/; fi
                    if [ ${isabl} -eq 1 ]; then mv ${TMPDIR}/*${CN_ABLRST_IN}*.nc ${CN_RST_DIR_IN}/; fi
                    if [ ${LNENSRST} -eq 1 ]; then mv ${TMPDIR}/*${CN_STORST_IN}*.nc ${CN_RST_DIR_IN}/; fi
                    if [ ${isas_cpl} -eq 1 ]; then mv ${TMPDIR}/*${CN_SASRST_IN}*.nc ${CN_RST_DIR_IN}/; fi
                else
                    echo "Hey! No restart files found in ${TMPDIR}/ either !!!"
                    echo "   => `basename ${fto}_0000.nc` and `basename ${fti}_0000.nc` ?"
                    exit
                fi
            fi
        done

        if [ ${inxs} -eq 1 ]; then
            echo; echo
            #
            # neXtSIM restarts, linking from "${RSTDIR_NXS}/out" to "${RSTDIR_NXS}":
            cd ${RSTDIR_NXS}/
            echo "Expected neXtSIM restarts:"
            for cnr in "mesh" "field"; do
                frnxs_b="${RSTDIR_NXS}/out/${cnr}_${SDATE}T000000Z.bin"
                frnxs_d="${RSTDIR_NXS}/out/${cnr}_${SDATE}T000000Z.dat"
                echo "  -> ${frnxs_b}"; echo "  -> ${frnxs_d}"
                check_on_file ${frnxs_b} ; check_on_file ${frnxs_d}
                ln -sf ${frnxs_b} ./${cnr}_final.bin ; ln -sf ${frnxs_d} ./${cnr}_final.dat ; #because "basename=final" into "cpl_run.cfg"...
            done
            echo "  => done with neXtSIM restarts!"; echo; echo
        fi
        cd ${TMPDIR}/
        #
        if [ ${ioa3} -eq 1 ]; then
            # OASIS restarts:
            echo; echo "Importing last OASIS restarts!"
            dirr=${RSTDIR_OA3}/${citend}
            echo " => from dir: ${dirr}/"
            if [ ! -d ${dirr} ]; then echo "PROBLEM: no such directory!!!"; exit; fi
            for coar in "ocean.nc" "ice.nc"; do
                check_on_file ${dirr}/${coar}
                ${CP}  ${dirr}/${coar} .
                ln -sf ${dirr}/${coar} ${coar}.lnk
            done
        fi
        cd ${TMPDIR}/

    fi ; # if [ ${irstrt} -eq 1 ]


    echo
    echo " Will start at day ${SDATE} and end at day ${EDATE}"
    echo " => this is submission # ${jsub}!"
    echo
    sleep 2
    #exit;#lolo1

    if [ ${jsub} -gt 1 ]; then
        # Need to know the start and end of previous go in terms of time steps...
        ciseg_prev=`cat ${TMPDIR}/0_last_success_iseg.info`
        istr=`echo ${ciseg_prev} | cut -d'-' -f1`; istr=`expr ${istr} + 0`
        iend=`echo ${ciseg_prev} | cut -d'-' -f2`; iend=`expr ${iend} + 0`
        #
        # to double check everything looks okay...
        iend2=`cat ${TMPDIR}/time.step`
        iend3=`cat ${TMPDIR}/0_last_success_icpt.info`
        if [ ${iend} -ne ${iend2} ] || [ ${iend} -ne ${iend3} ]; then
            echo "ERROR: time step disagreement: 'time.step', '0_last_success_iseg.info', '0_last_success_icpt.info' !"; exit
        fi
        echo " *** According to 0_last_success_iseg.info :"
        echo "    => Time steps completed during previous go: ${istr} to ${iend}"; echo
    fi

    CJY=`printf "%04d" ${JY}` ; CJYend=`printf "%04d" ${JYend}`
    JYM1=$((JY-1))
    JYP1=$((JY+1))

    # Shall we rely on a restart?
    l_start_from_restart=false
    if [ ${irstrt} -eq 1 ] || [ ${init_from_rstrt} -gt 0 ]; then l_start_from_restart=true; fi



    # Time to create the namelist
    # ---------------------------

    if [ ${init_from_rstrt} -gt 0 ] && ${l_respect_rstrt_time} ; then
        icpt=${init_from_rstrt}
    fi
    IT000=$((icpt+1)) ; ITEND=$((icpt+NLJOB))
    CITEND=`printf "%08d" ${ITEND}`

    if ${l_start_from_restart}; then
        RSTRT="true" ; IRCTL=2 ; TSD_INIT="false"
        if ! ${l_respect_rstrt_time} ; then IRCTL=0 ; fi
    fi


    # Ocean
    # -----

    # OPA will save its restarts into:
    CN_RST_DIR_OUT="${RSTDIR}/${CITEND}" ; mkdir -p ${CN_RST_DIR_OUT}
    if [ ${iagr} -eq 1 ]; then CN_RST_DIR_OUT_NST="./restarts/${CITEND}"; fi


    ############################## namelists ################################

    list_nml="namelist"
    if [ ${iagr} -eq 1 ]; then list_nml="namelist 1_namelist";   fi
    if [ ${isas_cpl} -eq 1 ]; then list_nml="namelist namelist_sas"; fi

    for fn in ${list_nml}; do

        if [ "${fn}" = "namelist_sas" ]; then subdir_nl="Namelists/sas"; fi
        # Namelist in the current directory
        fnamelist_o_cfg=${HERE}/${subdir_nl}/${fn}_cfg
        fnamelist_o_ref=${HERE}/${subdir_nl}/${fn}_ref

        check_on_file ${fnamelist_o_cfg}

        PCONF="${CONF}" ; # parent conf, needed for child as well...
        zconf="${CONF}" ; zconf_case="${CONFCASE}"
        znx="${NX}"     ; zny="${NY}"
        zdt=${DT}
        zit000=${IT000}
        zitend=${ITEND}
        znstock=${NSTOCK}
        znljob=${NLJOB}
        zcn_rst_dir_out="${CN_RST_DIR_OUT}"
        zcn_ocerst_in="${CN_OCERST_IN}"
	zcn_ablrst_in="${CN_ABLRST_IN}"
        zcn_storst_in="${CN_STORST_IN}"
        zcn_rst_dir_in="${CN_RST_DIR_IN}"
        znfsbc=${NFSBC}
        if [ "${fn}" = "1_namelist" ]; then
            zconf="${CONF_NST}"; zconf_case="${CASE}-${CONF_NST}"
            znx="${NX_NST}"    ; zny="${NY_NST}"
            zdt=${DT_n}
            zitend=$((ITEND*NST_RAT))
            znstock=${NSTOCK_n}
            znljob=${NLJOB_n}
            #itend_prev_n=$((zitend-znstock))
            itend_prev_n=$((icpt*NST_RAT))
            zit000=$((icpt*NST_RAT+1))
            znfsbc=$((NFSBC*NST_RAT))
            citend_prev_n=`printf "%08d" ${itend_prev_n}`
            if ${RSTRT}; then
                zcn_ocerst_in="${CASE}-${CONF_NST}_${citend_prev_n}_restart_oce"
                zcn_rst_dir_in="./restarts/`printf "%08d" $((ITEND-NLJOB))`"
            fi
            zcn_rst_dir_out="./restarts/${CITEND}" ; # yes same as mother
            #
            # SAS case:
        elif [ "${fn}" = "namelist_sas" ]; then
            znx="${NXA}"     ; zny="${NYA}"
            if ${RSTRT}; then zcn_ocerst_in=${CN_SASRST_IN}; fi
        fi

        sed -e "s/<CONF>/${zconf}/g" -e "s/<CONFCASE>/${zconf_case}/g" -e "s/<PCONF>/${CONF}/g" \
            -e "s/<IT000>/${zit000}/g" -e "s/<ITEND>/${zitend}/g" \
            -e "s/<DATE0>/${SDATE}/g" -e "s/<RSTRT>/${RSTRT}/g" -e "s/<IRCTL>/${IRCTL}/g" \
            -e "s/<NSTOCK>/${znstock}/g" -e "s/<NLJOB>/${znljob}/g" \
            -e "s|<CN_RST_DIR_IN>|${zcn_rst_dir_in}|g" -e "s|<CN_OCERST_IN>|${zcn_ocerst_in}|g" \
            -e "s|<CN_RST_DIR_OUT>|${zcn_rst_dir_out}|g" -e "s/<NZ>/${NZ}/g" \
            -e "s|<CN_ABLRST_IN>|${zcn_ablrst_in}|g" \
	    -e "s/<DT>/${zdt}/g" -e "s/<FSBC>/${znfsbc}/g" \
            -e "s/<TSD_INIT>/${TSD_INIT}/g" -e "s/<NEMOv>/${NEMOv}/g" \
            -e "s/<JPNI>/${znx}/g" -e "s/<JPNJ>/${zny}/g" -e "s/<JPNIJ>/${NCORES_NEM}/g" \
            -e "s/<IBC>/${IBC}/g" -e "s/<BDY>/${BDY}/g" -e "s/<Y1>/${Y1}/g" \
            -e "s/<SAS_OCE_FRC>/${SAS_OCE_FRC}/g" \
            -e "s/<FRQ_EC>/${FRQ_EC}/g" -e "s/<NI_EC>/${NI_EC}/g" -e "s/<NJ_EC>/${NJ_EC}/g" \
            -e "s/<NM_ATM_FORC>/${NM_ATM_FORC}/g" \
	    -e "s/<LNBLK>/${LNBLK}/g" \
            -e "s/<LNABL>/${LNABL}/g" \
	    -e "s/<RSTABL>/${RSTABL}/g" \
            -e "s/<LNENS>/${LNENS}/g" \
            -e "s/<LNENSRST>/${LNENSRST}/g" \
            -e "s|<CN_STORST_IN>|${zcn_storst_in}|g" \
            -e "s/<NMEMBER>/${NMEMBER}/g" \
            -e "s/<MEMBER0>/${MEMBER0}/g" \
	    -e "s/<LNSTOEOS>/${LNSTOEOS}/g" \
            -e "s/<CDice>/${CDice}/g" \
	    ${fnamelist_o_cfg} > ${TMPDIR}/${fn}_cfg.human

        ${CP} ${fnamelist_o_ref} ${TMPDIR}/${fn}_ref

        # Generating the CFG namelist, void of all crap:
        cat ${TMPDIR}/${fn}_cfg.human | grep -o '^[^!]*' | sed '/^\s*$/d' | sed -e s/' '/''/g > ${TMPDIR}/${fn}_cfg ; # problem for the 'NOT USED' in namelists...
        echo " *** ${TMPDIR}/${fn}_cfg generated!"; echo

        # Ice
        # ---
        ido1=0 ; ido2=0
        if [ ${isi3} -eq 1 ] && [ ${isas_cpl} -eq 0 ];            then ido1=1; fi
        if [ ${isas_cpl} -eq 1 ] && [ "${fn}" = "namelist_sas" ]; then ido2=1; fi
        if [ $((ido1+ido2)) -ge 1 ]; then
            fnamelist_i_cfg=${HERE}/${subdir_nl}/${fn}_ice_cfg
            fnamelist_i_ref=${HERE}/${subdir_nl}/${fn}_ice_ref
        fi
        if [ ${isi3} -eq 1 ] && [ "${fnamelist_i_cfg}" != "" ]; then
            sed -e "s|<CN_RST_DIR_IN>|${CN_RST_DIR_IN}|g" -e "s|<CN_ICERST_IN>|${CN_ICERST_IN}|g" \
                -e "s/<LNBBM>/${LNBBM}/g" \
		-e "s/<LNDAM>/${LNDAM}/g" \
                -e "s/<LNEVP>/${LNEVP}/g" \
		-e "s|<CN_RST_DIR_OUT>|${CN_RST_DIR_OUT}|g" -e "s/<DATE0>/${SDATE}/g" -e "s/<init_ice>/${init_ice}/g" \
                ${fnamelist_i_cfg} > ${TMPDIR}/${fn}_ice_cfg.human
            fnic="${TMPDIR}/${fn}_ice_cfg" ; fnir="${TMPDIR}/${fn}_ice_ref"
            if [ "${fn}" = "namelist_sas" ]; then fnic="${TMPDIR}/namelist_ice_cfg"; fnir="${TMPDIR}/namelist_ice_ref"; fi
            ${CP} ${fnamelist_i_ref} ${fnir}
            # Generating the CFG namelist, void of all crap:
            #cat ${TMPDIR}/${fn}_ice_cfg.human | grep -o '^[^!]*' | sed '/^\s*$/d' | sed -e s/' '/''/g > ${fnic} # problem for the 'NOT USED' in namelists...
            cat ${TMPDIR}/${fn}_ice_cfg.human | grep -o '^[^!]*' | sed '/^\s*$/d'   > ${fnic}
            echo " *** ${TMPDIR}/${fn}_ice_cfg generated!"; echo
        fi

    done ; #for fn in ${list_nml}
    ############################## namelists ################################
    #exit;#lolo2

    # AGRIF_FixedGrids.in
    if [ ${iagr} -eq 1 ]; then ${CP} ${DATA_CONF_DIR}/NST/AGRIF_FixedGrids.in ${TMPDIR}/; fi

    # Overwriting XML files (except for `file_def_*.xml`):
    list=`\ls ${HERE}/Namelists/*.xml | grep -v 'file_def_'`
    ${CP}                            ${list}                     ${TMPDIR}/
    if [ ${ioa3} -eq 1 ]; then ${CP} ${HERE}/Namelists/opa/*.xml ${TMPDIR}/; fi
    if [ ${isas_cpl} -eq 1 ]; then ${CP} ${HERE}/Namelists/sas/*.xml ${TMPDIR}/; fi

    if [ ${inxs} -eq 1 ]; then
        # neXtSIM + OASIS
        # ---------------
        fnamelist_x_cfg=${HERE}/Namelists/nxs/cpl_run_${NXS_BRANCH}.cfg
        check_on_file ${fnamelist_x_cfg}
        #
        TIME_INIT="`echo ${SDATE}|cut -c1-4`-`echo ${SDATE}|cut -c5-6`-`echo ${SDATE}|cut -c7-8`"
        sed -e "s|<MSH_FILE_NXS>|${MSH_FILE_NXS}|g" \
            -e "s|<SAVDIR_NXS>|${SAVDIR_NXS}|g" -e "s|<RSTDIR_NXS>|${RSTDIR_NXS}|g" \
            -e "s|<DT_SIA>|${DT_SIA}|g" -e "s|<DT_CPL>|${DT_CPL}|g" \
            -e "s|<NB_DAYS_TO_GO>|${NDAYS_EXP}|g" -e "s|<Y1>|${Y1}|g" \
            -e "s|<TIME_INIT>|${TIME_INIT}|g" -e "s/<RSTRT>/${RSTRT}/g" \
            ${fnamelist_x_cfg} > ${TMPDIR}/`basename ${fnamelist_x_cfg}`
        #
        fnmx=${TMPDIR}/`basename ${fnamelist_x_cfg}`
        echo " *** ${fnmx} generated!"; echo
        #
        fnmxb="${SAVDIR}/`basename ${fnamelist_x_cfg}`.nsub`printf "%04d" ${jsub}`"
        echo " => backing it up as: ${fnmxb} !"
        ${CP} ${fnmx} ${fnmxb}
        echo
    fi; #if [ ${inxs} -eq 1 ]

    if [ ${ioa3} -eq 1 ]; then
        # OASIS
        # -----
        # First we need to know the shape of the horizontal NEMO domain (JPI,JPJ)!
        #  => looking in the domain file as specified in the namelist:
        fdom=`cat ${TMPDIR}/${fn}_cfg | grep cn_domcfg | cut -d\' -f2 | sed -e "s|.nc|_${CONF}.nc|g"` ; fdom="${DATA_CONF_DIR}/${fdom}"
        check_on_file ${fdom}
        JPI=`ncdump -h ${fdom} | grep 'x = ' | head -1 | cut -d' ' -f3`
        JPJ=`ncdump -h ${fdom} | grep 'y = ' | head -1 |cut -d' ' -f3`
        echo; echo " *** Horizontal shape of NEMO domain => ${JPI} x ${JPJ}"; echo
        #
        cruntime=`printf "%08d" $((NDAYS_EXP*3600*24))`
        sed -e "s|<DT_CPL>|${DT_CPL}|g" -e "s|<DT_NEM>|${DT}|g" -e "s|<DT_SIA>|${DT_SIA}|g" \
            -e "s|<JPI>|${JPI}|g" -e "s|<JPJ>|${JPJ}|g" -e "s|<RUNTIME>|${cruntime}|g" \
            ${HERE}/Namelists/namcouple > ${TMPDIR}/namcouple
    fi; #if [ ${ioa3} -eq 1 ]

    CIT000=`printf "%08d" ${IT000}`
    CITEND=`printf "%08d" ${ITEND}`

    echo " *** Time steps that will be completed during go to be launched:"
    echo "       from CIT000=${CIT000} to CITEND=${CITEND}"
    ciseg_now="${CIT000}-${CITEND}"

    ITEND_prev=$((${ITEND}-${NLJOB}))
    if ${l_start_from_restart} && ${l_respect_rstrt_time} && [ ${ITEND_prev} -ne ${icpt} ]; then
        echo "PROBLEM: ITEND_prev and icpt disagree!!! ${ITEND_prev} and ${icpt}"; exit
    fi

    # Time tag information:
    CTI=${SDATE}_${EDATE}_${ciseg_now}

    # Backuping namelists into the log directory:
    logdir="${SAVDIR}/${ciseg_now}/logs" ; mkdir -p ${logdir}
    cinfo="${CTI}_nsub`printf "%04d" ${jsub}`"
    ${CP}                            ${TMPDIR}/namelist_cfg     ${logdir}/namelist.${cinfo}
    if [ ${isi3} -eq 1 ]; then ${CP} ${TMPDIR}/namelist_ice_cfg ${logdir}/namelist_ice.${cinfo} ; fi
    if [ ${iagr} -eq 1 ]; then ${CP} ${TMPDIR}/1_namelist_cfg   ${logdir}/1_namelist.${cinfo}   ; fi

    # Backuping pre-processed files we have selected into the src directory:
    if [ "${LIST_F90_BKP}" != "" ]; then
        echo; echo
        srcdir="${SAVDIR}/${ciseg_now}/src" ; mkdir -p ${srcdir}
        #NEM_EXE="${NEMO_REPO_DIR}/${cdir}/${CONFL}/BLD/bin/nemo.exe"
        cdbin=`dirname ${NEM_EXE}`
        cdpps=`echo ${cdbin} | sed -e "s|/BLD/bin|/BLD/ppsrc/nemo|g"`
        echo " *** Backuping following files of ${cdpps}:"
        for ff in ${LIST_F90_BKP}; do
            echo "      * ${ff}.f90"
            ${CP} ${cdpps}/${ff}.f90 ${srcdir}/ 2>/dev/null
        done
        echo "     ==> into ${srcdir} !"
        echo; echo
    fi


    # Installing required files if not a restart
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    if [ ${irstrt} -eq 0 ] || [ ! -f ${TMPDIR}/`basename ${NEM_EXE}` ]; then

        list_exe="${NEM_EXE}"
        if [ ${ioa3} -eq 1 ];              then list_exe="${list_exe} ${SIA_EXE}"; fi
        if [ ${NCORES_XIO_P_NODE} -ge 1 ]; then list_exe="${list_exe} ${XIO_EXE}"; fi
        for pexe in ${list_exe}; do
            fexe=`basename ${pexe}`
            check_on_file ${pexe}
            ${CP} ${pexe}                                  ${TMPDIR}/
            ln -sf ${pexe} ${fexe}.lnk ; mv -f ${fexe}.lnk ${TMPDIR}/
        done

        if [ ${ioa3} -eq 1 ]; then
            # OASIS stuff:
            if [ ! -d ${DATA_CONF_DIR}/OASIS ]; then echo "Hey! We need some OASIS restarts!!! (${DATA_CONF_DIR}/OASIS)"; exit ; fi
            for coar in "ocean" "ice"; do
                foar="${DATA_CONF_DIR}/OASIS/${coar}_${NSIA}.nc"
                check_on_file ${foar}
                ${CP} ${foar} ${TMPDIR}/${coar}.nc
            done
        fi

        # Installing configuration files:
        cd ${DATA_CONF_DIR}/
        list=`\ls *_${CONF}.nc`
        if [ ${iagr} -eq 1 ]; then list="${list} `\ls NST/1_*_${CONF}.nc`"; fi

        cd ${TMPDIR}/

        for ff in ${list}; do
            fn=`basename ${ff}`
            fn=`echo ${fn} | sed -e "s|_${CONF}.nc|.nc|g"`
            echo " ${DATA_CONF_DIR}/${ff}  => ${fn} (${CP} ...)"
            ${CP} ${DATA_CONF_DIR}/${ff} ${fn}  2>/dev/null
        done

        # Initial conditions for temperature and salinity:
        if [ "${IBC}" != "" ] && [ "${IBC}" != "none" ]; then
            cfs="${IBC}-${CONF}_L${NZ}_${SDATE0}.nc"
            lsini=`\ls ${DATA_CONF_DIR}/INIT_3D/*_${cfs} 2>/dev/null`
            if [ "${lsini}" != "" ]; then
                ${CP} ${DATA_CONF_DIR}/INIT_3D/*_${cfs} .
            fi
        fi

        # Initial conditions for sea-ice:
        if [ ${isi3} -eq 1 ] && [ ${init_ice} -ge 1 ]; then
            # Initial conditions for sea-ice:
            #  => will only be used if `nn_iceini_file=1` in namelist_ice...
            ff=${DATA_CONF_DIR}/INI_2D_ice/Ice_initialization_${SDATE}.nc ; check_on_file ${ff}            
            ${CP} ${ff} .
        fi

        if [ "${FBATHY}" != "" ]; then
            echo
            ff=${DATA_CONF_DIR}/${FBATHY} ; check_on_file ${ff}            
            echo "********************************************************************************"
            echo "*             We use this bathymetry:";         echo "  ${FBATHY}"
            ${CP}  ${ff} bathy_meter.nc
            ln -sf ${ff} bathy_meter.nc.lnk
            echo "********************************************************************************"; echo
        fi
        if [ "${FDMCFG}" != "" ]; then
            echo
            ff=${DATA_CONF_DIR}/${FDMCFG}
            check_on_file ${ff}
            echo "********************************************************************************"
            echo "*             We use this 'domain-config' file:";         echo "  ${FDMCFG}"
           echo ${ff}
	    ${CP}  ${ff} domain_cfg.nc
	    ${CP}  ${ff} domain_cfg_L${NZ}_${NEMOv}.nc
            ln -sf ${ff} domain_cfg.nc.lnk
            echo "********************************************************************************"; echo
        fi

        if [ ${isas_cpl} -eq 1 ]; then
            # Ini state for SAS:
            mkdir -p ${TMPDIR}/SAS
            ${CP} ${SIA_IN_DIR}/SAS_init_${CONF}_*.nc ${TMPDIR}/SAS/
        fi

        if [ ${inxs} -eq 1 ]; then
            mkdir -p ${TMPDIR}/nextsim_input
            cd ${TMPDIR}/nextsim_input/
            #
            for fn in "NpsNextsim.mpp"; do
                ff=${NEXTSIM_MESH_DIR}/${fn}
                check_on_file ${ff}
                ${CP}  ${ff} . ; ln -sf ${ff} ${fn}.lnk
            done
            #
            for fn in "ETOPO_NH25_10arcmin.nc" "ice_drift_nh_polstere-625_multi-oi.nc"; do
                ff=${NEXTSIM_DATA_DIR}/${fn}
                check_on_file ${ff}
                ${CP}  ${ff} . ; ln -sf ${ff} ${fn}.lnk
            done
            #
            for fn in "${MSH_FILE_NXS}" "NEMO_icemod.nc" "NEMO.nc"; do
                # All neXtSIM files related to this coupling with is in "${SIA_IN_DIR}"
                ff=${SIA_IN_DIR}/${fn}
                check_on_file ${ff}
                ${CP}  ${ff} .  ; ln -sf ${ff} ${fn}.lnk
            done
            #
            ln -sf ${FATM_SCR_DIR}/*_y*.nc .
            #
            # "coupler sub-dir:
            mkdir -p ${TMPDIR}/nextsim_input/coupler ; cd ${TMPDIR}/nextsim_input/coupler
            fn="NEMO.nc"; ff=${SIA_IN_DIR}/${fn}
            check_on_file ${ff}
            ${CP}  ${ff} .  ; ln -sf ${ff} ${fn}.lnk
            #
        fi

    else

        # This is a restarted year
        echo "Skipping installation of files..."; echo
        cd ${TMPDIR}/
        # Removing old shit:
        rm -f *.out *.err *.tmp tmp* >/dev/null

    fi  # ${irstrt} -eq 0



    # Installing required files, even if it is a restart
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    cd ${TMPDIR}/
    if [ "${BDY}" != "" ] && [ "${BDY}" != "none" ]; then
        mkdir -p ./BDY
        cd ./BDY/
        ${CP} ${DATA_CONF_DIR}/BDY/*${BDY}*_${CONF}_L${NZ}_y${JYM1}.nc .  2>/dev/null
        ${CP} ${DATA_CONF_DIR}/BDY/*${BDY}*_${CONF}_L${NZ}_y${JY}.nc .    2>/dev/null
        ${CP} ${DATA_CONF_DIR}/BDY/*${BDY}*_${CONF}_L${NZ}_y${JYP1}.nc .  2>/dev/null
        #
        if ${ltide}; then
            ${CP} ${DATA_CONF_DIR}/BDY/bdytide_*-${CONF}_*.nc .  2>/dev/null
        fi
        cd ../
    fi

    if [ "${RNF}" != "" ] && [ "${RNF}" != "none" ]; then
        mkdir -p ./RNF
        cd ./RNF/
        ${CP} ${DATA_CONF_DIR}/RNF/*${RNF}*_y${JYM1}.nc .   2>/dev/null
        ${CP} ${DATA_CONF_DIR}/RNF/*${RNF}*_y${JY}.nc .     2>/dev/null
        ${CP} ${DATA_CONF_DIR}/RNF/*${RNF}*_y${JYP1}.nc .   2>/dev/null
        cd ../
    fi

    if [ ${isas_ssx} -eq 1 ]; then
        # Prescribed surface ocean state for SAS:
        mkdir -p ${TMPDIR}/SAS
        cd ${TMPDIR}/SAS
        ${LNK} ${DATA_CONF_DIR}/SAS/${SAS_OCE_FRC}*.nc .
        cd ${TMPDIR}/
    fi
    

    # Copying atmospheric forcing stuff (files + weights)
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    echo ; echo

    echo " *** Importing Atmospheric Forcing!"; echo
    # Keeping scractch version of the dir up-to-date:
    if [ "${FATM_SCR_DIR}" != "" ]; then
        mkdir -p ${FATM_SCR_DIR}
        cd ${FATM_SCR_DIR}/
        ${LNK} ${FATM_REF_DIR}/*_y*.nc  .  2>/dev/null
        if [ ${i_interp_fatm_exists} -eq 1 ]; then ${LNK} ${DIR_FATM_ITRP}/*_y*.nc .  2>/dev/null ; fi
        echo " Scratch version of FATM repo up-to-date!"; echo
    else
        FATM_SCR_DIR=${FATM_REF_DIR}
    fi
    #
    echo "    => ${FATM_SCR_DIR}"
    if [ ${inxs} -eq 1 ]; then
        cd ${TMPDIR}/nextsim_input/
    else
        cd ${TMPDIR}/
        mkdir -p ./${FATM_S_DIR} ;  cd ./${FATM_S_DIR}/
        echo "${LNK} ${DATA_CONF_DIR}/${FATM_S_DIR}/weight_*_${NM_ATM_FORC}*${CONF}.nc ."
        ${LNK} ${DATA_CONF_DIR}/${FATM_S_DIR}/weight_*_${NM_ATM_FORC}*${CONF}.nc .  2>/dev/null
        echo
    fi

    ${LNK} ${FATM_SCR_DIR}/*_y${JY}.nc .
    ${LNK} ${FATM_SCR_DIR}/*_y$((JY-1)).nc . 2>/dev/null
    ${LNK} ${FATM_SCR_DIR}/*_y$((JY+1)).nc . 2>/dev/null

    if [ ${i_interp_fatm_exists} -eq 1 ]; then ${LNK} ${DIR_FATM_ITRP}/*_y*.nc .; fi
    #
    if [ ${iagr} -eq 1 ]; then
        ${LNK} ${DATA_CONF_DIR}/NST/1_${FATM_S_DIR}/weight_*_${NM_ATM_FORC}*${CONF_NST}.nc .
        cd ../
        if [ ! -L 1_${FATM_S_DIR} ]; then ${LNK} ${FATM_S_DIR} 1_${FATM_S_DIR}; fi
    fi


    if [ ${isabl} -eq 1 ]; then
	    echo "============= copy ABL stuff "
    echo ${ABLDIR}/dom_cfg_abl*.nc
    echo ${TMPDIR}/
    cd ${TMPDIR}/
    ### SLX
     echo "SLX ??????????????????
     echo  ${ABLDIR}/ERA5*_y${JY}*.nc" 
     ${LNK} ${ABLDIR}/ERA5*_y${JY}*.nc ./FATM/
     ${CP} ${ABLDIR}/dom_cfg_abl*.nc .
     ${CP}  ${ABLDIR}/weights*_ABL.nc ./FATM/ 
   fi
    
    # Done installing stuff...



    # Write/Save directory for run to come:
    SDIR="${SAVDIR}/${ciseg_now}" ; mkdir -p ${SDIR}

    # Adapting the `file_def_<component>_<freq>.xml` so XIOS can write in right directory:
    list_xml="${HERE}/Namelists/file_def_nemo-oce_${xios_freq_oce}.xml"
    if [ ${isi3} -eq 1 ]; then list_xml+=" ${HERE}/Namelists/file_def_nemo-ice_${xios_freq_ice}.xml"; fi
    for ff in ${list_xml}; do
        check_on_file ${ff}
        fn=`basename ${ff} | sed -e s/"_${xios_freq_oce}"/""/g -e s/"_${xios_freq_ice}"/""/g`
        sed -e "s|{CONFIG}|${CONF}|g" -e "s|{CASE}|${CASE}|g" -e "s|{DATE0}|${SDATE}|g" -e "s|{SAVDIR}|${SDIR}|g" \
            ${ff} > ${TMPDIR}/${fn}
        echo "${HERE}/${subdir_nl}/${fn} > ${TMPDIR}/${fn}"; echo
    done
    # Server or not server for XIOS?
    using_server="true"
    if [ ${NCORES_XIO_P_NODE} -eq 0 ]; then using_server="false"; fi
    sed -e "s|{using_server}|${using_server}|g" \
        ${HERE}/Namelists/iodef.xml > ${TMPDIR}/iodef.xml

    # SLX
    # Ensemble simulations
    tag=""
    for member in $(seq $MEMBER0 $MEMBERN) ; do
       if [ $LNENS = "true" ] ; then
         echo "test ENS XML================"
         tag=`echo ${member} | awk '{printf("%03d", $1)}'`
	 echo $tag
       fi
       sed -e "/%NEMO_CONTEXT%/ r context_nemo_ens.xml" <${TMPDIR}/iodef.xml  >${TMPDIR}/iodef.tmp ; mv ${TMPDIR}/iodef.tmp ${TMPDIR}/iodef.xml
       sed -e "s/%NMEMBER%/$tag/"                    <${TMPDIR}/iodef.xml  >${TMPDIR}/iodef.tmp ; mv ${TMPDIR}/iodef.tmp ${TMPDIR}/iodef.xml
done
sed -e "s/%NEMO_CONTEXT%//"                     <${TMPDIR}/iodef.xml  >${TMPDIR}/iodef.tmp ; mv ${TMPDIR}/iodef.tmp ${TMPDIR}/iodef.xml



    # Previous time tag
    # -----------------
    if [ ${FREQ_RST_Y} -eq 0 ]; then
        if [ ${JDy} -eq 1 ]; then
            jdend_prev=${nbdy} ; jd_prev=$((${jdend_prev}-${FREQ_RST_D}))
            JYM1=$((${JY}-1))
        else
            jd_prev=$((${JDy}-${FREQ_RST_D})) ; jdend_prev=$((${JDy}-1))
            JYM1=${JY}
        fi
        SDATEM1=`printf "%04d" ${JYM1}``day_year_to_MMDD $((${jd_prev}>1?${jd_prev}:1)) ${JYM1}` ; # max(${jd_prev}:1)
        EDATEM1=`printf "%04d" ${JYM1}``day_year_to_MMDD $((${jdend_prev}>1?${jdend_prev}:1)) ${JYM1}`
    else
        JYM1=$((${JY}-1*${FREQ_RST_Y}));       CJYM1=`printf "%04d" ${JYM1}`
        JYendM1=$((${JYend}-1*${FREQ_RST_Y})); CJYendM1=`printf "%04d" ${JYendM1}`
        SDATEM1=${CJYM1}0101
        EDATEM1=${CJYendM1}1231
    fi

    if [ ${FREQ_RST_D} -eq 0 ] && [ "${SDATE}" = "${JY}0101" ]; then
        CTIM1=${SDATE}_${EDATE} ; # same as CTI !!!
    else
        # Normal case:
        CTIM1=${SDATEM1}_${EDATEM1}
    fi
    #exit;#lolo3

    # Time to launch the experiment !
    # ===============================

    ${CP} ${TMPDIR}/namelist*_cfg ${logdir}/

    if [ ${iagr} -eq 1 ]; then
        SDIR_NST=${SDIR}/NST ; mkdir -p ${SDIR_NST}
        mkdir -p ./1_/${SAVDIR}
        cd ./1_/${SAVDIR}
        if [ ! -L ${ciseg_now} ]; then ln -sf ${SDIR_NST} ${ciseg_now}; fi
        cd ${TMPDIR}/
    fi


    # Moving previous job stderr and stdout into previous SDIR:
    cd ${HERE}/
    if [ ${jsub} -gt 1 ]; then
        mkdir -p ${SAVDIR}/${ciseg_prev}/logs
        for ff in "out_${CONFCASE}_" "err_${CONFCASE}_" "${TMPDIR}/*ocean.output" "${TMPDIR}/*.stat"; do
            mv -f ${ff}* ${SAVDIR}/${ciseg_prev}/logs 2>/dev/null
        done
        ${CP} ${TMPDIR}/0_last_success_*.info ${TMPDIR}/*time.step ${TMPDIR}/*ocean.output   ${SAVDIR}/${ciseg_prev}/logs  2>/dev/null
    fi
    rm -f *.tmp *.out *.err ; # cleaning

    # Create the submission script:
    # =============================

    cproc_shape="`printf "%03d" ${NX}`x`printf "%03d" ${NY}`_`printf "%03d" ${NCORES_NEM}`"
    if [ ${ioa3} -eq 1 ]; then   cproc_shape="${cproc_shape}_`printf "%03d" ${NCORES_SIA}`"; fi

    sub_scr="run_${CONFCASE}_${CTI}.tmp"
    rm -f ${sub_scr}

    OPT_SRUN=""
    if [ "${ARCH}" = "ADASTRA" ] && [ ${idouble} -eq 1 ]; then
        NCORES_TOT=$((NNODES_TOT*NBCPN/2))
        #OPT_SRUN="-c1 -m cyclic"
        OPT_SRUN="-c1"
    fi

    # Using template header for bash job manager script:

    if [ "${JOBMNGR}" = "none" ]; then

        echo "#!/bin/bash"          > ${sub_scr}
        echo "ulimit -s unlimited" >> ${sub_scr}

    else

        fjm=${NCM_DIR}/misc/job_mngr_headers/${JOBMNGR}_header_template.bash
        fjt=${NCM_DIR}/misc/job_mngr_headers/${JOBMNGR}_header_${ARCHB}.bash
        if [ -f ${fjt} ]; then fjm=${fjt}; fi
        check_on_file ${fjm}
        #
        jm_sub_cmd="sbatch"
        if [ "${JOBMNGR}" = "OAR" ]; then jm_sub_cmd="oarsub -S"; fi

        cat ${fjm} | grep -v '^###' | \
                     sed -e "s|<NNODES_TOT>|${NNODES_TOT}|g" -e "s|<NCORES2BOOK>|${NCORES_TOT}|g" \
                         -e "s|<CASE>|${CASE}|g" -e "s|<CONFCASE>|${CONFCASE}|g" -e "s|<CTI>|${CTI}|g" \
                         -e "s|<cproc_shape>|${cproc_shape}|g" -e "s|<TJOB>|${TJOB}|g" \
                         -e "s|<QUEUE_OPTION>|${QUEUE_OPTION}|g" -e "s|<cpu_type>|${cpu_type}|g" > ${sub_scr}
        if [ "${ARCHB}" = "MEOMCAL1" ]; then echo "#SBATCH --mem=32000"    >> ${sub_scr}; fi
    fi
echo "============="
echo "============="
echo ${sub_scr}
echo ${NCORES_TOT}
echo "============="
echo "============="
    cat >> ${sub_scr} <<EOF
################################
#
ulimit -s unlimited
date
#
PD=${TMPDIR}; # prod. directory
#
echo
echo "######################################################"
echo " *** Nb cores for xios: ${NCORES_XIO}"
echo " *** Nb cores for nemo: ${NCORES_NEM}"
echo " *** Nb of ensemble members: ${NMEMBER}"
echo " ***      JPNI: ${NX}"
echo " ***      JPNJ: ${NY}"
echo " ***        DT: ${DT}"
EOF
    if [ ${ioa3} -eq 1 ]; then echo "echo \" *** Nb cores for ${NMSIA}: ${NCORES_SIA}\"" >> ${sub_scr}; fi
    cat >> ${sub_scr} <<EOF
echo " *** JOB walltime: ${TJOB}"
echo "######################################################"
echo; echo
#
env | grep ${JOBMNGR} > ${JOBMNGR}_env.tmp
#
EOF
    if [ ${inxs} -eq 1 ]; then
        cat >> ${sub_scr} <<EOF
export NEXTSIMDIR=${NEXTSIMDIR}
export NEXTSIM_DATA_DIR=\${PD}/nextsim_input
export NEXTSIM_MESH_DIR=\${PD}/nextsim_input
#
export LD_LIBRARY_PATH=\${NEXTSIMDIR}/lib:\${LD_LIBRARY_PATH}
#
EOF
    fi

    nemo_exe=`basename ${NEM_EXE}`

    # SAS-ICE or neXtSIM command-line:
    if [ ${inxs} -eq 1 ]; then
        cmd_sia="./`basename ${SIA_EXE}` --config-files=`basename ${fnamelist_x_cfg}` -mat_mumps_icntl_23 ${MMI}"
    fi
    if [ ${isas_cpl} -eq 1 ]; then
        cmd_sia="./`basename ${SIA_EXE}`"
    fi

    # Default MPIRUN commands:
    if [ ${ioa3} -eq 1 ]; then
        # OPA - <SIA>:
        if [ ${NCORES_XIO_P_NODE} -eq 0 ]; then
            CMD="mpirun -n ${NCORES_NEM} ./${nemo_exe} : -n ${NCORES_SIA} ${cmd_sia}"
        else
            CMD="mpirun -n ${NCORES_XIO} ./xios_server.exe : -n ${NCORES_NEM} ./${nemo_exe} : -n ${NCORES_SIA} ${cmd_sia}"
        fi
    else
        # NEMO alone (OPA or OPA-SI3):
        if [ ${NCORES_XIO_P_NODE} -eq 0 ]; then
            #CMD="mpirun -n ${NCORES_NEM} ./${nemo_exe}"
	    # SLX
            CMD="srun -m cyclic -n ${NCORES_NEM} ./${nemo_exe}"
        else
            #CMD="mpirun -n ${NCORES_NEM} ./${nemo_exe} : -n ${NCORES_XIO} ./xios_server.exe"
            # SLX
       CMD="srun -v -m cyclic -n ${NCORES_NEM} ./${nemo_exe} : -n ${NCORES_XIO} ./xios_server.exe"
    fi
    fi

    # Default `srun` command:
    lic="0"; ic=1
    while [ ${ic} -lt ${NPPN} ]; do lic="${lic},${ic}"; ic=`expr ${ic} + 1`; done
    CMD_SRUN="srun -N ${NNODES_TOT} --mpi=pmi2 -m cyclic --cpu_bind=map_cpu:${lic} --multi-prog ./ztask_file.conf"

    case ${ARCHB} in
        #
        "MEOMCAL1")
            #
            cat >> ${sub_scr} <<EOF
export INTEL_ONEAPI="/mnt/meom/workdir/brodeau/opt/intel/oneapi"
export NCDF_INTEL="/mnt/meom/workdir/brodeau/opt/hdf5_netcdf4_intel_par"
export PATH=\${INTEL_ONEAPI}/compiler/latest/linux/bin/intel64:${PATH}
export LD_LIBRARY_PATH=\${INTEL_ONEAPI}/compiler/latest/linux/compiler/lib/intel64_lin:${LD_LIBRARY_PATH}
export INTEL_MPI_DIR="\${INTEL_ONEAPI}/mpi/latest"
export PATH=${INTEL_MPI_DIR}/bin:${PATH}
export LD_LIBRARY_PATH=${INTEL_MPI_DIR}/lib:${LD_LIBRARY_PATH}
export LD_LIBRARY_PATH=\${NCDF_INTEL}/lib:${LD_LIBRARY_PATH}
#
CMD="${CMD}"
EOF
            ;;
        "ADASTRA")
            #
            cat >> ${sub_scr} <<EOF
#
unset I_MPI_SHM_SEND_TINY_MEMCPY_THRESHOLD
unset I_MPI_DAPL_DIRECT_COPY_THRESHOLD
#
export OMP_NUM_THREADS=1
#
EOF
            #
            #NCTN=$((NCORES_NEM + NIDLE_GCM_CORES))
            NCTN=$((NCORES_NEM))
            #
            if [ ${NCORES_XIO_P_NODE} -eq 0 ]; then
                if [ ${inxs} -eq 1 ]; then
                    echo "0-$((NCTN-1))               ./${nemo_exe}" >  ${TMPDIR}/ztask_file.conf
                    echo "${NCTN}-$((NCORES_GCM-1))   ${cmd_sia}"          >> ${TMPDIR}/ztask_file.conf
                    echo "CMD=\"${CMD_SRUN}\""                                       >> ${sub_scr}
                else
                    echo "CMD=\"srun --mpi=pmi2 -n ${NCORES_NEM} ${OPT_SRUN} ./${nemo_exe}\"" >> ${sub_scr} ; #  -m cyclic
                fi
                #
            elif [ ${NNODES_XIO} -eq 0 ]; then
                # "NNODES_XIO=0" & "NCORES_XIO_P_NODE>0" => xios tasks are spread out on every nodes
                if [ ${ioa3} -eq 1 ]; then
                    #
                    rm -f ${TMPDIR}/ztask_file.conf
                    jn=0 ; plast=0 ; # number of last used proc
                    ncxpn=$((NCORES_XIO_P_NODE)) ; ncnpn=$((NCORES_NEM_P_NODE)) ; ncspn=$((NCORES_SIA_P_NODE))
                    while [ ${jn} -lt ${NNODES_TOT} ]; do
                        pnn=$((plast+ncxpn-1))
                        echo "$((plast))-${pnn} ./xios_server.exe"          >> ${TMPDIR}/ztask_file.conf
                        pnn=$((pnn+ncnpn))
                        echo "$((plast+ncxpn))-${pnn} ./${nemo_exe}"           >> ${TMPDIR}/ztask_file.conf
                        pnn=$((pnn+ncspn))
                        echo "$((plast+ncxpn+ncnpn))-${pnn} ${cmd_sia}" >> ${TMPDIR}/ztask_file.conf
                        plast=$((pnn+1))
                        jn=$((jn+1))
                    done
                else
                    rm -f ${TMPDIR}/ztask_file.conf
                    jn=0 ; plast=0 ; # number of last used proc
                    ncxpn=$((NCORES_XIO_P_NODE)) ; ncnpn=$((NCORES_NEM_P_NODE))
                    while [ ${jn} -lt ${NNODES_TOT} ]; do
                        echo "$((plast))-$((plast+ncxpn-1)) ./xios_server.exe" >> ${TMPDIR}/ztask_file.conf
                        pnn=$((plast+ncxpn+ncnpn-1))
                        echo "$((plast+ncxpn))-${pnn} ./${nemo_exe}"              >> ${TMPDIR}/ztask_file.conf
                        plast=$((pnn+1))
                        jn=$((jn+1))
                    done
                fi
                #                
                CMD="srun -N ${NNODES_TOT} --mpi=pmi2 -m cyclic -K1 --multi-prog ./ztask_file.conf"
                #CMD="srun -N ${NNODES_TOT} --mpi=pmi2 -m cyclic -K1 --cpu_bind=map_cpu:${lic} --multi-prog ./ztask_file.conf" ; # 
                echo "CMD=\"${CMD}\"" >> ${sub_scr}
                #
            elif [ ${NNODES_XIO} -gt 0 ]; then
                # NNODES_XIO=${NNODES_XIO} dedicated nodes to xios tasks (${NCORES_XIO_P_NODE} tasks per node)
                echo "0-$((NCORES_NEM-1)) ./${nemo_exe}"                      >  ${TMPDIR}/mpmd.tmp
                echo "${NCORES_NEM}-$((NCORES_TOT-1)) ./xios_server.exe"     >> ${TMPDIR}/mpmd.tmp
                #
                cat >> ${sub_scr} <<EOF
# Need to create the host list file:
list_nodes_c=\`scontrol show hostname ${SLURM_NODELIST} | paste -d, -s\`
list_nodes=\`echo \${list_nodes_c} | sed -e s/','/' '/g\`
echo \${list_nodes_c} > node_list.out
echo; echo "  *** JOB ID => \${SLURM_JOB_ID} "; echo "  *** Nodes to be booked:"; echo "\${list_nodes} !"; echo
#
rm -f \${PD}/machine_file.tmp host_file.tmp nodes_xios.tmp
list_nodes_xios=""
ip=0
for nd in \${list_nodes}; do
    if [ \${ip} -lt ${NNODES_GCM} ]; then
        for i in \`seq 1 ${NCORES_NEM_P_NODE}\`; do
            echo "\${nd}" >> \${PD}/machine_file.tmp
        done
    else
        list_nodes_xios="\${list_nodes_xios} \${nd}"
        echo "\${nd}" >> nodes_xios.tmp
        for i in \`seq 1 ${NCORES_XIO_P_NODE}\`; do
            echo "\${nd}" >> \${PD}/machine_file.tmp
        done
    fi
    echo "\${nd}" >> host_file.tmp
    ip=\`expr \${ip} + 1\`
done
#
nb_nodes=\`echo \${list_nodes} | wc -w\`
if [ ! \${nb_nodes} -eq ${NNODES_TOT} ]; then echo "ERROR: nb_nodes /= NNODES_TOT !!!"; exit; fi
#
export SLURM_HOSTFILE=machine_file.tmp
unset SLURM_TASKS_PER_NODE
env | grep SLURM > slurm_env_\${SLURM_JOBID}.tmp
#
CMD="srun --mpi=pmi2 -m arbitrary --multi-prog ./mpmd.tmp"
#

EOF
            else
                echo "PROBLEM: NNODES_XIO + NCORES_XIO_P_NODE configuration makes no sense!!!"; exit
            fi
            ;;
        #
        #
        "FRAM")
            #
            if [ ${NCORES_XIO_P_NODE} -eq 0 ]; then
                if [ ${inxs} -eq 1 ]; then
                    cat >> ${sub_scr} <<EOF
CMD="mpirun -n ${NCORES_NEM} ./${nemo_exe} : -n ${NCORES_SIA} ${cmd_sia}"
EOF
                else
                    # FRAM without NXS and with no XIOS server:
                    cat >> ${sub_scr} <<EOF
CMD="mpirun -n ${NCORES_NEM} ./${nemo_exe}"
EOF
                fi
                #
            elif [ ${NNODES_XIO} -eq 0 ]; then
                # "NNODES_XIO=0" & "NCORES_XIO_P_NODE>0" => xios tasks are spread out on every nodes
                if [ ${inxs} -eq 1 ]; then
                    echo " FRAM with NXS => fix me!"; exit
                else
                    cat >> ${sub_scr} <<EOF
list_nodes_c=\`scontrol show hostname ${SLURM_NODELIST} | paste -d, -s\`
list_nodes=\`echo \${list_nodes_c} | sed -e s/','/' '/g\`
echo \${list_nodes_c} > node_list.out
#
lcmd=""
for hh in \${list_nodes}; do
   cs=": "
   if [ "\${lcmd}" = "" ]; then cs=""; fi
   lcmd="\${lcmd} \${cs}-host \${hh} -n ${NCORES_NEM_P_NODE} ./${nemo_exe} : -host \${hh} -n ${NCORES_XIO_P_NODE} ./xios_server.exe"
done
CMD="mpirun -perhost ${NPPN1} \${lcmd}"
EOF
                fi
                #
            elif [ ${NNODES_XIO} -gt 0 ]; then
                cat >> ${sub_scr} <<EOF
export I_MPI_PIN=enable
EOF
                licN="0"; ic=1
                while [ ${ic} -lt ${NCORES_NEM_P_NODE} ]; do licN="${licN},${ic}"; ic=`expr ${ic} + 1`; done
                licX="0"; ic=1
                while [ ${ic} -lt ${NCORES_XIO_P_NODE} ]; do licX="${licX},${ic}"; ic=`expr ${ic} + 1`; done
                #
                cat >> ${sub_scr} <<EOF
list_nodes_c=\`scontrol show hostname ${SLURM_NODELIST} | paste -d, -s\`
list_nodes=\`echo \${list_nodes_c} | sed -e s/','/' '/g\`
echo \${list_nodes_c} > node_list.out
echo; echo "  *** JOB ID => \${SLURM_JOB_ID} "; echo "  *** Nodes to be booked:"; echo "\${list_nodes} !"; echo

VHOST=( \${list_nodes} )

CMD="mpirun -m \\
       -host \${VHOST[0]} -env I_MPI_PIN_PROCESSOR_LIST=${licX} -n ${NCORES_XIO} ./xios_server.exe :\\
       -host \${VHOST[1]} -env I_MPI_PIN_PROCESSOR_LIST=${licN} -n ${NCORES_NEM} ./${nemo_exe}"

#
EOF
            else
                echo "PROBLEM: NNODES_XIO + NCORES_XIO_P_NODE configuration makes no sense!!!"; exit
            fi
            ;;
        #
        #
        # DEFAULTS:
        *)
            cat >> ${sub_scr} <<EOF
CMD="${CMD}"
EOF
            ;;
    esac

    # Final part of the job:
    cat >> ${sub_scr} <<EOF
#
cd \${PD}/
#
echo \${CMD}
echo "\#BOF"
\${CMD}
echo "\#EOF"

# Things to do before quitting job!
#na=\`cat \${PD}/ocean.output 2>/dev/null | grep AAAAAAAA | wc -l\`
if [ -f \${PD}/001ocean.output ]; then
    # If 001ocean.output exists, count occurrences of AAAAAAAA in it
    na=\$(grep -c "AAAAAAAA" \${PD}/001ocean.output 2>/dev/null)
elif [ -f \${PD}/ocean.output ]; then
    # If 001ocean.output doesn't exist, fall back to ocean.output
    na=\$(grep -c "AAAAAAAA" \${PD}/ocean.output 2>/dev/null)
else
    # If neither file exists, set na to 0
    na=0
fi
if [ \${na} -eq ${naaa} ] && [ ! -f \${PD}/output.abort_0000.nc ] && [ ! -f \${PD}/1_output.abort_0000.nc ]; then
    # => the job has terminated properly!
    echo "${EDATE}"         > \${PD}/0_last_success_date.info
    echo "${jsub}"          > \${PD}/0_last_success_jsub.info
    echo "${NLJOB}"         > \${PD}/0_last_success_nljb.info
    echo "${ciseg_now}"     > \${PD}/0_last_success_iseg.info
    cat \${PD}/time.step > \${PD}/0_last_success_icpt.info
    # Also save them to the log dir:
    ${CP} \${PD}/0_last_success_*.info              ${logdir}/
    ${CP} \${PD}/*ocean.output \${PD}/*time.step ${logdir}/
    ${CP} \${PD}/*restart_sto*.nc ${RSTDIR}/ 
    ${CP} \${PD}/*human  ${logdir}/
    #
    if [ ${IDEBUG} -eq 1 ]; then
        # Also the job manager standard O/E:
       cd ${HERE}/
       ${CP} out_${CONFCASE}_${CTI}_${cproc_shape}_\${SLURM_JOBID}.out ${logdir}/
       ${CP} err_${CONFCASE}_${CTI}_${cproc_shape}_\${SLURM_JOBID}.err ${logdir}/
    fi
    #
EOF
    if [ ${ioa3} -eq 1 ]; then
        cat >> ${sub_scr} <<EOF
    #
    if [ ! -f \${PD}/ice.nc ] || [ ! -f \${PD}/ocean.nc ]; then echo " MISSING 'ice.nc' or 'ocean.nc' in \${PD}!"; exit; fi
    ${CP} \${PD}/ice.nc \${PD}/ocean.nc ${RSTDIR_OA3}/${CITEND}/
EOF
    fi
    cat >> ${sub_scr} <<EOF
else
    echo "Mhhh... Seems like the job has fucked up... (not updating the '0_last_success*' files)"; echo
fi
exit
EOF
    chmod +x ${sub_scr}
   #exit ; #lolo4
    echo; echo "Submitting ${sub_scr} ..."

    if [ "${JOBMNGR}" = "none" ]; then
        nohup ./${sub_scr} > JOB.out &
        #
    else
        ${jm_sub_cmd} ./${sub_scr}
    fi

    if [ ${IDEBUG} -eq 1 ]; then echo " We exit because IDEBUG=${IDEBUG}!"; exit; fi

    echo ; echo " Sleeping 15 seconds..."; sleep 15; echo

    # Waiting until the batch job is over...
    lb_wait ${CASE}

    cd ${TMPDIR}/

    echo ; echo

    # Time to launch post-treatment:
    na=`cat ${TMPDIR}/ocean.output 2>/dev/null | grep AAAAAAAA | wc -l`
    if [ ${na} -eq ${naaa} ]; then
        if ${launch_post_trtmt}; then
            echo ; echo " *** Launching : ${POST_TRTMT} into:"; echo "    ${SDIR}"
            cd ${SDIR}/
            ${POST_TRTMT}
        fi
    fi

    echo ; echo

    cd ${TMPDIR}/

done ; # loop along years...

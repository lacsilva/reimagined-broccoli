!***********************************************************************
!
!***********************************************************************
#include "errorcodes.h"
#include "version.h"
program CriticalRaEff
   use parameters
   use GrowthRateMod
   use CritRaEff_io
   use glo_constants
   implicit none
   type GlobalCrit
      double precision:: alpha
      double precision:: Ra
      double precision:: w
      integer:: m
   end type
   integer, parameter:: NN = 3600
   character*60:: infile,outfile
   integer, parameter:: unitOut=16
   double precision:: alphas(NN)
   type(GlobalCrit):: crit(NN)

!---------------------------------------------------------
!  arg #1 - filename or usage ?
   call getarg(1,infile)
   if (infile.eq.' ' .or. infile.eq.'-h') then
      print*, 'Usage : '
      print*, 'CriticalRaEff <in file> <out file>'
      stop
   endif

   call getarg(2,outfile)
   print*,  trim(infile),' - ',trim(outfile)

   call init(trim(infile))
   Print*, 'Out of init()'

   call createAlphas(alphas)
   select case(LCALC)
      case(0)
         ! Single m
         call computeCriticalCurveSingleM(alphas,crit)
      case(1)
         ! Global
         call computeCriticalCurve(alphas,crit)
   end select

contains

   !**********************************************************************
   !> Initialises things.
   subroutine init(inputfile)
      implicit none
      CHARACTER(len=*), intent(in)::  inputfile

      ! ----Default values:
      call setDefaults()
      ! ----INPUT:
      call readConfigFileNew(inputfile)

      ! ---- doesn't work for M=0 !!!!!!
      IF(M0.LT.1) THEN
        write(*,*) 'The code does not work for M0<1. ', M0, ' --> 1'
        M0 = 1
      ENDIF

      call GrowthRateInitAlpha(Ra, alpha, Pt, Le, tau, eta, m0, Symmetry, Truncation)
      call setVariableParam('Ra ')

   end subroutine

   !**********************************************************************
   subroutine createAlphas(alphas)
      implicit none
      double precision, intent(out):: alphas(:)
      double precision:: dalpha
      integer:: n, i
      n=size(alphas,1)
      dalpha=2.0d0*dpi/n
      alphas(1)=-dpi

      do i=2, n
         alphas(i) = alphas(i-1) + dalpha
      enddo
   end subroutine

   !**********************************************************************
   !> Computes the lowest critical effective Rayleigh number as a function of alpha
   !! for all other parameters fixed.
   subroutine computeCriticalCurveM(alpha, crit)
      implicit none
      character(8)  :: date
      character(10) :: time
      double precision, intent(in):: alpha(:)
      double precision, intent(out):: crit(:,:)
      double precision:: CriticalRa, CriticalRaAlpha0
      double precision:: RaMin, RaMax, gr1,gr2
      integer:: i, N, HalfN
      integer:: info, counter

      N     = size(alphas,1)
      HalfN = N/2
      Write(*,*) N, HalfN
      info  = 0
      crit(:,1) = huge(1.0d0)
      crit(:,2) = 0.0d0

      RaMin = 0
      RaMax = 10*Ra
      call GrowthRateUpdateParAlpha(alpha=0.0d0)
      ! At this point a critical Ra is certain to exist so,
      ! increase the interval, until we find it.
      do
         gr1 = MaxGrowthRate(RaMin)
         gr2 = MaxGrowthRate(RaMax)
         if (gr1*gr2.gt.0.0d0) then
            RaMin = RaMax
            RaMax = 2*RaMax
         else
            exit
         endif
      enddo
      counter=0
      ! Now that we found an interval find the critical value for Ra.
      call minimizer(MaxGrowthRate, RaMin, RaMax, RELE ,ABSE, NSMAX, CriticalRa, info)
      ! Cache this value for future use.
      CriticalRaAlpha0 = CriticalRa
      ! Compute the positive half of the alphas
      do i=HalfN, N
         call GrowthRateUpdateParAlpha(Ra=CriticalRa, alpha=alpha(i))
         RaMin = 0.05d0*CriticalRa
         RaMax = 100.d0*CriticalRa
         call minimizer(MaxGrowthRate, RaMin, RaMax, RELE ,ABSE, NSMAX, CriticalRa, info)
         if (info.NE.0) then
            ! We test 3 more points after we failed just in case we
            ! hit an asymptote.
            Write(*,*) 'counter = ', counter
            if (counter==3) then
               counter = 0
               exit
            else
               counter = counter + 1
               CriticalRa = (RaMin+RaMax)/2.0
               cycle
            endif
         else
            counter = 0
         endif
         call date_and_time(DATE=date,TIME=time)
         Write(*,*) '[',date,'-',time,']', ' alpha = ', alpha(i), CriticalRa
         crit(i,1) = CriticalRa
         crit(i,2) = dble(MaxGrowthRateCmplx(CriticalRa))
         if (mod(i,5)==0 ) call writeCriticalCurveSingleM(alpha, crit, m0)
      enddo
      info = 0
      CriticalRa = CriticalRaAlpha0
      ! and the negative half
      do i=HalfN-1, 1, -1
         call GrowthRateUpdateParAlpha(Ra=CriticalRa, alpha=alpha(i))
         RaMin = 0.05d0*CriticalRa
         RaMax = 100.d0*CriticalRa
         call minimizer(MaxGrowthRate, RaMin, RaMax, RELE ,ABSE, NSMAX, CriticalRa, info)
         if (info.NE.0) then
            Write(*,*) 'counter = ', counter
            if (counter==3) then
               exit
            else
               counter = counter + 1
               CriticalRa = (RaMin+RaMax)/2.0
               cycle
            endif
         else
            counter = 0
         endif
         call date_and_time(DATE=date,TIME=time)
         Write(*,*) '[',date,'-',time,']', ' alpha = ', alpha(i), CriticalRa
         crit(i,1) = CriticalRa
         crit(i,2) = dble(MaxGrowthRateCmplx(CriticalRa))
         if (mod(i,5)==0 ) call writeCriticalCurveSingleM(alpha, crit, m0)
      enddo
   end subroutine

   !**********************************************************************
   !>
   subroutine computeCriticalCurve(alpha, crit)
      implicit none
      double precision, intent(in):: alpha(:)
      type(GlobalCrit), intent(out):: crit(:)
      double precision, allocatable:: crit_new(:,:)
      integer:: m, N, i
      integer:: info

      N = size(alpha,1)
      allocate(crit_new(N,2))
      info = 0
      crit_new(:,1) = huge(1.0d0)
      crit_new(:,2) = 0.0d0
      do i=1, N
         crit(i)%alpha = alpha(i)
         crit(i)%m  = Huge(1)
         crit(i)%w  = Huge(1.0d0)
         crit(i)%Ra = Huge(1.0d0)
      enddo

      do m=1, m0
         call GrowthRateUpdateParAlpha(m=m)
         Write(*,*) 'Computing critical value for m =', m
         if(wasPreviouslyComputed(m)) then
            call readCriticalCurveSingleM(crit_new,m)
         else
            call computeCriticalCurveM(alpha, crit_new)
            call writeCriticalCurveSingleM(alpha, crit_new, m)
         endif
         do i=1,N
            if(crit_new(i,1).lt.crit(i)%Ra) then
               crit(i)%Ra = crit_new(i,1)
               crit(i)%w  = crit_new(i,2)
               crit(i)%m  = m
            endif
         enddo
         call writeCriticalCurve(crit)
      enddo
      deallocate(crit_new)
   end subroutine

   !**********************************************************************
   !>
   subroutine computeCriticalCurveSingleM(alpha, crit)
      implicit none
      double precision, intent(in):: alpha(:)
      type(GlobalCrit), intent(out):: crit(:)
      double precision, allocatable:: crit_new(:,:)
      integer:: N, i
      integer:: info

      N     = size(alpha,1)
      allocate(crit_new(N,2))
      info  = 0
      crit_new(:,1) = huge(1.0d0)
      crit_new(:,2) = 0.0d0
      call GrowthRateUpdateParAlpha(m=m0)
      Write(*,*) 'Computing critical value for m =', m0
      if(wasPreviouslyComputed(m0)) then
         call readCriticalCurveSingleM(crit_new,m0)
      else
         call computeCriticalCurveM(alpha, crit_new)
         call writeCriticalCurveSingleM(alpha, crit_new, m0)
      endif
      do i=1,N
         crit(i)%alpha = alpha(i)
         crit(i)%Ra = crit_new(i,1)
         crit(i)%w  = crit_new(i,2)
         crit(i)%m  = m0
      enddo
      deallocate(crit_new)
   end subroutine

   !**********************************************************************
   !>
   subroutine writeCriticalCurve(crit)
      implicit none
      type(GlobalCrit), intent(in):: crit(:)
      integer:: N, i
      ! ----OUTPUT:
      OPEN(unitOut,FILE=outfile,STATUS='UNKNOWN')
      call writeOutputHeader(unitOut)
      N = size(crit,1)
      do i=1, N
         if (crit(i)%Ra.ge.huge(1.0d0)) then
            Write(unitOut,*) crit(i)%alpha, ' NaN ', ' NaN ' , ' NaN'
         else
            Write(unitOut,*) crit(i)%alpha, crit(i)%Ra, crit(i)%m, crit(i)%w  
         endif
      enddo
      close(unitOut)
   end subroutine

   !**********************************************************************
   !>
   subroutine writeCriticalCurveSingleM(alpha, crit, m)
      implicit none
      double precision, intent(in):: alpha(:)
      double precision, intent(in):: crit(:,:)
      integer, intent(in):: m
      character(len=3):: num
      integer:: N, i
      integer, parameter:: unitm=999
      N = size(crit,1)
      Write(num,'(I3.3)') m
      open(unit=unitm,file=trim(outfile)//'.'//trim(num), status='UNKNOWN')
      do i=1, N
         Write(unitm,*) alpha(i), crit(i,1), crit(i,2)
      enddo
      close(unitm)
   end subroutine
   
   !**********************************************************************
   !>
   subroutine readCriticalCurveSingleM(crit, m)
      implicit none
      double precision, intent(out):: crit(:,:)
      integer, intent(in):: m
      double precision:: alpha
      character(len=3):: num
      integer:: N, i
      integer, parameter:: unitm=999
      N = size(crit,1)
      Write(num,'(I3.3)') m
      open(unit=unitm,file=trim(outfile)//'.'//trim(num), status='OLD')
      do i=1, N
         ! TODO: Deal with the possibility that the files may not have been
         !       written at the same resolution.
         read(unitm,*) alpha, crit(i,1), crit(i,2)
      enddo
      close(unitm)
   end subroutine
   
   !**********************************************************************
   !> 
   logical function wasPreviouslyComputed(m)
      implicit none
      integer, intent(in):: m
      character(len=3):: num
      Write(num,'(I3.3)') m
      inquire(file=trim(outfile)//'.'//trim(num), EXIST=wasPreviouslyComputed)
   end function
end program
! vim: tabstop=3:softtabstop=3:shiftwidth=3:expandtab

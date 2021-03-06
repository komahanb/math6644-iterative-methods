!=====================================================================!
! Run gradient-based descent algorithms to solve linear algebra
!=====================================================================!

program test

  implicit none

  call check_conjugate

end program test

!---------------------------------------------------------------------!
! 
!---------------------------------------------------------------------!

subroutine check_conjugate

  use linear_algebra

  implicit none

  dirichlet : block

    integer, parameter :: npts = 64
    real(8), parameter :: max_tol = 1.0d-8
    integer, parameter :: max_it = 100000
    real(8) :: x(npts,3), b(npts), A(npts,npts), P(npts, npts)
    integer :: iter, flag, i, j
    real(8) :: tol

    ! Solve using LU factorization
    call assemble_system_dirichlet(0.0d0, 1.0d0, npts, A, b, x(:,1), P)
    x(:,1) = solve(A,b)

    ! solve using CG
    call assemble_system_dirichlet(0.0d0, 1.0d0, npts, A, b, x(:,2), P) 
    call dcg(A, b, max_it, max_tol, x(:,2), iter, tol, flag)
    print *, 'cg', tol, iter

    ! Solve using preconditioned CG
    call assemble_system_dirichlet(0.0d0, 1.0d0, npts, A, b, x(:,3), P) 
    call dpcg(A, P,  b, max_it, max_tol, x(:,3), iter, tol, flag)
    print *, 'pcg', tol, iter 

    open(11, file='dirichlet.dat')
    do i = 1, npts
       ! x, exact, xcg, xpcg
       write(11, *) dble(i)/dble(npts+1), x(i,1), x(i,2), x(i,3)
    end do
    close(11)

  end block dirichlet

  mixed : block

    integer, parameter :: npts = 256
    real(8), parameter :: max_tol = 1.0d-8
    integer, parameter :: max_it = 100000
    real(8) :: x(npts+1,3), b(npts+1), A(npts+1,npts+1), P(npts+1, npts+1)
    integer :: iter, flag, i, j
    real(8) :: tol

    ! Solve using LU factorization
    call assemble_system_mixed(0.0d0, 1.0d0, npts, A, b, x(:,1), P)
    x(:,1) = solve(A,b)

    ! Solve using CG
    call assemble_system_mixed(0.0d0, 1.0d0, npts, A, b, x(:,2), P) 
    call dcg(A, b, max_it, max_tol, x(:,2), iter, tol, flag)
    print *, 'cg', tol, iter

    ! Solve using preconditioned CG
    call assemble_system_mixed(0.0d0, 1.0d0, npts, A, b, x(:,3), P) 
    call dpcg(A, P,  b, max_it, max_tol, x(:,3), iter, tol, flag)
    print *, 'pcg', tol, iter

    open(11, file='mixed.dat')
    do i = 1, npts + 1
       write(11, *) dble(i)/dble(npts+1), x(i,1), x(i,2), x(i,3)
    end do
    close(11)

  end block mixed

end subroutine check_conjugate

!---------------------------------------------------------------------!
! Assemble -U_xx = 2x - 0.5, U(0) = 1;  U(1)= 0, x in [0,1]
!---------------------------------------------------------------------!

subroutine assemble_system_dirichlet(a, b, npts, V, rhs, u, P)

  use linear_algebra, only : inv

  implicit none
  
  real(8), intent(in)  :: a, b ! bounds of the domain
  integer, intent(in)  :: npts ! number of interior points
  real(8), intent(out) :: V(npts,npts) ! banded matrix
  real(8), intent(out) :: rhs(npts)
  real(8), intent(out) :: u(npts)
  real(8), intent(out) :: P(npts,npts)
  real(8) :: S(npts,npts), D(npts, npts)
  
  real(8), parameter :: PI = 3.141592653589793d0
  real(8)            :: h, alpha
  integer            :: M, N
  integer            :: i, j, k
  
  ! h = width / num_interior_pts + 1
  h = (b-a)/dble(npts+1)
  V = 0.0d0

  ! Size of the linear system = unknowns (interior nodes)
  M = npts ! nrows
  N = npts ! ncols
  
  ! Set the inner block
  rows: do i = 1, M
     cols: do j = 1, N
        if (j .eq. i-1) then
           ! lower triangle
           V(j,i) = -1.0d0
        else if (j .eq. i+1) then           
           ! upper triangle
           V(j,i) = -1.0d0
        else if (j .eq. i) then           
           ! diagonal
           V(j,i) = 2.0d0
        else
           ! skip
        end if
     end do cols
  end do rows
  
  ! Assemble the RHS
  do i = 1, M
     rhs(i) = h*h*(2.0d0*dble(i)*h - 0.5d0)
  end do
  rhs(1) = rhs(1) + 1.0d0
  rhs(M) = rhs(M)

  ! Initial solution profile use sin function as a first guess
  do i = 1, M
     u(i) =  sin(dble(i)*h*PI)
  end do

  ! Find the sine transform matrix
  alpha = sqrt(2.0d0/dble(npts+1))
  do j = 1, M
     do k = 1, N
        S(k,j) = alpha*sin(PI*dble(j*k)/dble(npts+1))
     end do
  end do

  ! Find the diagonal matrix
  D = matmul(S, matmul(V, S))

  ! Invert the digonal matrix easily
  do j = 1, M
     D(j,j) = 1.0d0/D(j,j)
  end do
  
  ! Define the preconditioner
  p = matmul(S, matmul(D, S))

end subroutine assemble_system_dirichlet

!---------------------------------------------------------------------!
! Assemble -U_xx = 2x - 0.5, U(0) = U_x(1)= 0, x in [0,1]
!---------------------------------------------------------------------!

subroutine assemble_system_mixed(a, b, npts, V, rhs, u, P)

  use linear_algebra, only : inv

  implicit none
  
  real(8), intent(in)  :: a, b ! bounds of the domain
  integer, intent(in)  :: npts ! number of interior points
  real(8), intent(out) :: V(npts+1,npts+1) ! banded matrix
  real(8), intent(out) :: rhs(npts+1)
  real(8), intent(out) :: u(npts+1)
  real(8), intent(out) :: P(npts+1,npts+1)
  real(8) :: S(npts+1, npts+1), D(npts+1, npts+1)
  real(8), parameter :: PI = 3.141592653589793d0
  real(8)            :: h, alpha
  integer            :: M, N
  integer            :: i, j, k
  
  ! h = width / num_interior_pts + 1
  h = (b-a)/dble(npts+1)
  V = 0.0d0

  ! Size of the linear system = unknowns
  M = npts + 1 ! nrows
  N = npts + 1 ! ncols
  
  ! Set the inner block
  rows: do i = 1, M
     cols: do j = 1, npts
        if (j .eq. i-1) then
           ! lower triangle
           V(j,i) = -1.0d0
        else if (j .eq. i+1) then           
           ! upper triangle
           V(j,i) = -1.0d0
        else if (j .eq. i) then           
           ! diagonal
           V(j,i) = 2.0d0
        else
           ! skip
        end if
     end do cols
  end do rows
  V(M,M) = 1.0d0
  V(M,N-1) = -1.0d0

  ! Assemble the RHS
  do i = 1, M
     rhs(i) = h*h*(2.0d0*dble(i)*h - 0.5d0)
  end do
  rhs(1) = rhs(1) + 1.0d0
  rhs(M) = rhs(M)/2.0d0

  ! Initial solution profile use sin function as a first guess
  do i = 1, M
     u(i) = sin(dble(i)*h*PI)
  end do
  ! Find the sine transform matrix
  alpha = sqrt(2.0d0/dble(npts+1))
  do j = 1, M
     do k = 1, N
        S(k,j) = alpha*sin(PI*dble(j*k)/dble(npts+1))
     end do
  end do

  ! Find the diagonal matrix
  D = matmul(S, matmul(V, S))

  ! Invert the digonal matrix easily
  do j = 1, M
     D(j,j) = 1.0d0/D(j,j)
  end do
  
  ! Define the preconditioner
  p = matmul(S, matmul(D, S))

end subroutine assemble_system_mixed

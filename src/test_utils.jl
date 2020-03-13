using LinearAlgebra

function block_gemm!(C,A,B,a,b,bsize)
    rmul!(C,b)
    ni,nj  = size(C)
    nk     = size(A,2)
    nbi    = div(ni,bsize[1])
    nbj    = div(nj,bsize[2])
    nbk    = div(nk,bsize[3])
    for j = 1:nbj
        jrange = (j-1)*bsize[2]+1:j*bsize[2]
        for i = 1:nbi
            irange = (i-1)*bsize[1]+1:i*bsize[1]
            Cview  = view(C,irange,jrange)
            for k = 1:nbk
                krange = (k-1)*bsize[3]+1:k*bsize[3]
                Bview  = view(B,krange,jrange)
                Aview  = view(A,irange,krange)
                mul!(Cview,Aview,Bview,a,1)
            end
        end
    end
    return C
end

function plan_block_gemm!(C,A,B,a,b,bsize,tg=TaskGraph())
    cl = Codelet(cpu_func=rmul!,data=(C,b),access_modes=(RW,R),
                 label="$b * C")
    insert_task!(tg,cl)
    ni,nj  = size(C)
    nk     = size(A,2)
    nbi    = div(ni,bsize[1])
    nbj    = div(nj,bsize[2])
    nbk    = div(nk,bsize[3])
    for j = 1:nbj
        jrange = (j-1)*bsize[2]+1:j*bsize[2]
        for i = 1:nbi
            irange = (i-1)*bsize[1]+1:i*bsize[1]
            Cview  = view(C,irange,jrange)
            for k = 1:nbk
                krange = (k-1)*bsize[3]+1:k*bsize[3]
                Bview  = view(B,krange,jrange)
                Aview  = view(A,irange,krange)
                cl     = Codelet(cpu_func=mul!,data=(Cview,Aview,Bview,a,1),access_modes=(RW,R,R,R,R),
                                 label="C[$i,$j]+A[$i,$k]*B[$k,$j]")
                insert_task!(tg,cl)
            end
        end
    end
    return tg
end

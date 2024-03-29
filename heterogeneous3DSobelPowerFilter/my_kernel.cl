/*
 *  myKernel.cl
 *  heterogeneous3DSobelPowerFilter
 *
 *
 *  Created by Beau Johnston on 25/08/11
 *  Copyright (C) 2011 by Beau Johnston.
 *
 *  Please email me if you have any comments, suggestions or advice:
 *                              beau@inbeta.org
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to deal
 *  in the Software without restriction, including without limitation the rights
 *  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 *  THE SOFTWARE.
 */



#pragma OPENCL EXTENSION cl_khr_fp64 : enable

#define FastFourierTransform
#define VolumetricRendering
#define InternalStructureWithDICOMColouration
//#define InternalStructure
//#define MarchingCubes
//#define RegularPlanar


// function prototypes to avoid openCL compiler warning
__local static inline float8 FFT(int,long,float4,float4);
__local static inline float8 DFT(int,int,float4,float4);

__local static inline int FFTCPU(int,long,float*,float*);
__local static inline int DFTCPU(int,int,float*,float*);

__global static inline float4 getFillColour(void);

__global static float4 getFillColour(void){
    return (float4) (1.0f,0.5f,0.0f,1);
}

/* ----------------------------------> Real Utility functions start here <------------------------------ */

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

#ifndef BOOL 
#define BOOL unsigned int
#endif

#ifndef NULL 
#define NULL ((void *)0)
#endif

#define FFT_FORWARD 1
#define FFT_REVERSE -1

/*
 This computes an in-place complex-to-complex FFT
 x and y are the real and imaginary arrays of 2^m points.
 dir =  1 gives forward transform
 dir = -1 gives reverse transform
 */
__local static inline float8 FFT(int dir,long m,float4 xIn,float4 yIn){
    float x[4];
    float y[4];
    
    x[0] = xIn.x;
    x[1] = xIn.y;
    x[2] = xIn.z;
    x[3] = xIn.w;
    
    y[0] = yIn.x;
    y[1] = yIn.y;
    y[2] = yIn.z;
    y[3] = yIn.w;
    
	long n,i,i1,j,k,i2,l,l1,l2;
	float c1,c2,tx,ty,t1,t2,u1,u2,z;
    
	// Calculate the number of points
	n = 1;
	for (i=0;i<m;i++)
		n *= 2;
    
	// Do the bit reversal
	i2 = n >> 1;
	j = 0;
	for (i=0;i<n-1;i++) {
		if (i < j) {
			tx = x[i];
			ty = y[i];
			x[i] = x[j];
			y[i] = y[j];
			x[j] = (float)tx;
			y[j] = (float)ty;
		}
		k = i2;
		while (k <= j) {
			j -= k;
			k >>= 1;
		}
		j += k;
	}
    
	// Compute the FFT
	c1 = -1.0;
	c2 = 0.0;
	l2 = 1;
	for (l=0;l<m;l++) {
		l1 = l2;
		l2 <<= 1;
		u1 = 1.0;
		u2 = 0.0;
		for (j=0;j<l1;j++) {
			for (i=j;i<n;i+=l2) {
				i1 = i + l1;
				t1 = u1 * x[i1] - u2 * y[i1];
				t2 = u1 * y[i1] + u2 * x[i1];
				x[i1] = (float)(x[i] - t1);
				y[i1] = (float)(y[i] - t2);
				x[i] += (float)t1;
				y[i] += (float)t2;
			}
			z =  u1 * c1 - u2 * c2;
			u2 = u1 * c2 + u2 * c1;
			u1 = z;
		}
        //c2 = (float)pow((float)((1.0 - c1) / 2.0),1/2);
		c2 = (float)sqrt((float)((1.0f - c1) / 2.0f));
		if (dir == FFT_FORWARD){
			c2 = -c2;
        }
        //c1 = (float)pow((float)((1.0+c1)/2),1/2);
		c1 = (float)sqrt((float)((1.0 + c1) / 2.0));
	}
    
	// Scaling for forward transform
	if (dir == FFT_FORWARD) {
		for (i=0;i<n;i++) {
			x[i] /= n;
			y[i] /= n;
		}
	}
    
    float8 Out = (float8)(0.0f,0.0f,0.0f,0.0f,0.0f,0.0f,0.0f,0.0f);
    Out.s0 = x[0];
    Out.s1 = x[1];
    Out.s2 = x[2];
    Out.s3 = x[3];
    
	Out.s4 = y[0];
    Out.s5 = y[1];
    Out.s6 = y[2];
    Out.s7 = y[3];
    
    return Out;
}

/*
 Direct fourier transform
 */
__local static inline float8 DFT(int dir,int m,float4 xIn,float4 yIn)
{
    
    float x1[4];
    float y1[4];

    float x2[4];
    float y2[4];

    
    x1[0] = xIn.x;
    x1[1] = xIn.y;
    x1[2] = xIn.z;
    x1[3] = xIn.w;
    
    y1[0] = yIn.x;
    y1[1] = yIn.y;
    y1[2] = yIn.z;
    y1[3] = yIn.w;
    
    long i,k;
    float arg;
    float cosarg,sinarg;
    
    for (i=0;i<m;i++) {
        x2[i] = 0;
        y2[i] = 0;
        arg = - dir * 2.0 * 3.141592654 * (float)i / (float)m;
        for (k=0;k<m;k++) {
            cosarg = cos(k * arg);
            sinarg = sin(k * arg);
            x2[i] += (x1[k] * cosarg - y1[k] * sinarg);
            y2[i] += (x1[k] * sinarg + y1[k] * cosarg);
        }
    }
    
    /* Copy the data back */
    if (dir == 1) {
        for (i=0;i<m;i++) {
            x1[i] = x2[i] / (float)m;
            y1[i] = y2[i] / (float)m;
        }
    } else {
        for (i=0;i<m;i++) {
            x1[i] = x2[i];
            y1[i] = y2[i];
        }
    }
    
    float8 Out = (float8)(0.0f,0.0f,0.0f,0.0f,0.0f,0.0f,0.0f,0.0f);
    Out.s0 = x1[0];
    Out.s1 = x1[1];
    Out.s2 = x1[2];
    Out.s3 = x1[3];
    
	Out.s4 = y1[0];
    Out.s5 = y1[1];
    Out.s6 = y1[2];
    Out.s7 = y1[3];
    
    return Out;
}


__local static inline int FFTCPU(int dir,long m,float *x,float *y){
	long n,i,i1,j,k,i2,l,l1,l2;
	double c1,c2,tx,ty,t1,t2,u1,u2,z;
    
	// Calculate the number of points
	n = 1;
	for (i=0;i<m;i++)
		n *= 2;
    
	// Do the bit reversal
	i2 = n >> 1;
	j = 0;
	for (i=0;i<n-1;i++) {
		if (i < j) {
			tx = x[i];
			ty = y[i];
			x[i] = x[j];
			y[i] = y[j];
			x[j] = (float)tx;
			y[j] = (float)ty;
		}
		k = i2;
		while (k <= j) {
			j -= k;
			k >>= 1;
		}
		j += k;
	}
    
	// Compute the FFT
	c1 = -1.0;
	c2 = 0.0;
	l2 = 1;
	for (l=0;l<m;l++) {
		l1 = l2;
		l2 <<= 1;
		u1 = 1.0;
		u2 = 0.0;
		for (j=0;j<l1;j++) {
			for (i=j;i<n;i+=l2) {
				i1 = i + l1;
				t1 = u1 * x[i1] - u2 * y[i1];
				t2 = u1 * y[i1] + u2 * x[i1];
				x[i1] = (float)(x[i] - t1);
				y[i1] = (float)(y[i] - t2);
				x[i] += (float)t1;
				y[i] += (float)t2;
			}
			z =  u1 * c1 - u2 * c2;
			u2 = u1 * c2 + u2 * c1;
			u1 = z;
		}
		c2 = sqrt((1.0 - c1) / 2.0);
		if (dir == FFT_FORWARD)
			c2 = -c2;
		c1 = sqrt((1.0 + c1) / 2.0);
	}
    
	// Scaling for forward transform
	if (dir == FFT_FORWARD) {
		for (i=0;i<n;i++) {
			x[i] /= n;
			y[i] /= n;
		}
	}
    
	return 1;
}

/*
 Direct fourier transform
 */
__local static inline int DFTCPU(int dir,int m,float *x1,float *y1)
{
    long i,k;
    float arg;
    float cosarg,sinarg;
    float *x2=NULL,*y2=NULL;
    
    x2 = malloc(m*sizeof(float));
    y2 = malloc(m*sizeof(float));
    if (x2 == NULL || y2 == NULL)
        return(FALSE);
    
    for (i=0;i<m;i++) {
        x2[i] = 0;
        y2[i] = 0;
        arg = - dir * 2.0 * 3.141592654 * (float)i / (float)m;
        for (k=0;k<m;k++) {
            cosarg = cos(k * arg);
            sinarg = sin(k * arg);
            x2[i] += (x1[k] * cosarg - y1[k] * sinarg);
            y2[i] += (x1[k] * sinarg + y1[k] * cosarg);
        }
    }
    
    /* Copy the data back */
    if (dir == 1) {
        for (i=0;i<m;i++) {
            x1[i] = x2[i] / (float)m;
            y1[i] = y2[i] / (float)m;
        }
    } else {
        for (i=0;i<m;i++) {
            x1[i] = x2[i];
            y1[i] = y2[i];
        }
    }
    
    free(x2);
    free(y2);
    return(TRUE);
}


__kernel
void testGPU(__read_only image3d_t srcImg,
             __write_only image3d_t dstImg,
             sampler_t sampler,
             int width, int height, int depth)
{
//    int x = get_group_id(0) + get_global_id(0);
//    int y = get_group_id(1) + get_local_id(1);
//    int z = get_group_id(2) + get_local_id(2);
//    
//    if(((int)(x%3) != (int)0) || ((int)(y%3) != (int)0) || ((int)(z%3) != (int)0)){
//        return;
//    }
//    
//    int4 startImageCoord = (int4) (x - 1, y - 1, z - 1, 1);
//    int4 endImageCoord   = (int4) (x + 1, y + 1, z + 1, 1);
//    int4 outImageCoord = (int4) (x, y, z, 1);
//    
//    if (outImageCoord.x < width && outImageCoord.y < height && outImageCoord.z < depth)
//    {
//        float4 thisIn = (float4)(0.0f, 0.0f, 0.0f, 0.0f);
//        
//        float DaR[3*3*3];
//        float DaI[3*3*3];
//        
//        float4 WriteDaR[3*3*3];
//        float4 WriteDaI[3*3*3];
//
//        for(int c = 0; c < 3; c++){
//            for(int z = startImageCoord.z; z <= endImageCoord.z; z++){
//                for(int y = startImageCoord.y; y <= endImageCoord.y; y++){
//                    for(int x = startImageCoord.x; x <= endImageCoord.x; x++){
//                        thisIn = read_imagef(srcImg, sampler, (int4)(x,y,z,1));
//                        if(c == 0){
//                            DaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)] = (float)thisIn.x;
//                        }
//                        else if(c == 1){
//                            DaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)] = (float)thisIn.y;
//                        }
//                        else{
//                            DaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)] = (float)thisIn.z;
//                        }
//                        DaI[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)] = (float)0.0f;
//                    }
//                }
//            }
//            
//            if(c == 0){
//                for (int i = 0; i < 3; i ++) {
//                    for (int j = 0; j < 3; j ++) {
//                        for (int k = 0; k < 3; k ++) {
//                            WriteDaR[(i*3*3)+(j*3)+k].x = (float)DaR[(i*3*3)+(j*3)+k];
//                            WriteDaI[(i*3*3)+(j*3)+k].x = (float)DaI[(i*3*3)+(j*3)+k];
//                        }
//                    }
//                }
//            }
//            else if(c == 1){
//                for (int i = 0; i < 3; i ++) {
//                    for (int j = 0; j < 3; j ++) {
//                        for (int k = 0; k < 3; k ++) {
//                            WriteDaR[(i*3*3)+(j*3)+k].y = (float)DaR[(i*3*3)+(j*3)+k];
//                            WriteDaI[(i*3*3)+(j*3)+k].y = (float)DaI[(i*3*3)+(j*3)+k];                        }
//                    }
//                }
//            }
//            else{
//                for (int i = 0; i < 3; i ++) {
//                    for (int j = 0; j < 3; j ++) {
//                        for (int k = 0; k < 3; k ++) {
//                            WriteDaR[(i*3*3)+(j*3)+k].z = (float)DaR[(i*3*3)+(j*3)+k];
//                            WriteDaI[(i*3*3)+(j*3)+k].z = (float)DaI[(i*3*3)+(j*3)+k];
//                        }
//                    }
//                }
//            }
//        }
//        
//        //write this channel out
//        for(int z = startImageCoord.z; z <= endImageCoord.z; z++){
//            for(int y = startImageCoord.y; y <= endImageCoord.y; y++){
//                for(int x= startImageCoord.x; x <= endImageCoord.x; x++){
//                    #ifdef VolumetricRendering
//                    if(WriteDaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)].x > 0.05f && WriteDaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)].y > 0.05f && WriteDaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)].z > 0.05f){
//                        write_imagef(dstImg, (int4)(x,y,z,1),(float4)(WriteDaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)].x,WriteDaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)].y,WriteDaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)].z,1)); 
//                        //write_imagef(dstImg, outImageCoord, (float4)(WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z,1));
//                    }
//                    #else
//                    //output over these output coordinates
//                    write_imagef(dstImg, (int4)(x,y,z,1),(float4)(WriteDaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)].x,WriteDaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)].y,WriteDaR[(z - startImageCoord.z)*3*3 + (y - startImageCoord.y)*3 + (x - startImageCoord.x)].z,1)); 
//                    #endif
//                }
//            }
//        }
//    }
    
}

/* --------------------------> Real work happens past this point <--------------------------------- */
__kernel
void sobel3D(__read_only image3d_t srcImg,
           __write_only image3d_t dstImg,
           sampler_t sampler,
           int width, int height, int depth)
{

//    int x = (int)get_global_id(0);
//    int y = (int)get_global_id(1);
//    int z = (int)get_global_id(2);
    
    //this approach is needed for working with workgroups
    int x = get_group_id(0) + get_local_id(0);
    int y = get_group_id(1) + get_local_id(1);
    int z = get_group_id(2) + get_local_id(2);
    
    //3*3*3 window do computation on
    if(x%3 != 0 || y%3 != 0 || z%3 != 0){
        return;
    }
    
    //w is ignored? I believe w is included as all data types are a power of 2
    int4 startImageCoord = (int4) (x - 1,
                                   y - 1,
                                   z - 1, 
                                   1);
    
    int4 endImageCoord   = (int4) (x + 1,
                                   y + 1, 
                                   //remove plus 1 to get indexing proper
                                   z + 1 /* + 1*/, 
                                   1);
    
    int4 outImageCoord = (int4) (x,
                                 y,
                                 z, 
                                 1);
    
    if (outImageCoord.x < width && outImageCoord.y < height && outImageCoord.z < depth)
    {
        float4 thisIn = (float4)(0.0f, 0.0f, 0.0f, 0.0f);

        float DaR[3][3][3];
        float DaI[3][3][3];
        
        float4 WriteDaR[3][3][3];
        float4 WriteDaI[3][3][3];

        
        for(int c = 0; c < 3; c++){
        //first collect the red channel, then green than blue
        for(int z = startImageCoord.z; z <= endImageCoord.z; z++){
            for(int y = startImageCoord.y; y <= endImageCoord.y; y++){
                for(int x = startImageCoord.x; x <= endImageCoord.x; x++){
                    thisIn = read_imagef(srcImg, sampler, (int4)(x,y,z,1));
                    if(c == 0){
                    DaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = thisIn.x;
                    }
                    else if(c == 1){
                    DaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = thisIn.y; 
                    }
                    else{
                    DaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = thisIn.z;
                    }
                    DaI[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = 0.0f;
                }
            }
        }
        
        float DatR[4][4][4];
        float DatI[4][4][4];
        
        
        //set out 4 window size (need 3 for correct filter focus, however need to be dyadic for fft, solution use window 
        //size of 4*4*4 whilst only populating the 3*3*3 and padding the rest with zeros)
        for(int i = 0; i < 4; i++){
            for(int j = 0; j < 4; j++){
                for(int k = 0; k < 4; k++){
                    if (k == 3 || j == 3 || i == 3) {
                        DatR[i][j][k] = 0;
                        DatI[i][j][k] = 0;
                    }
                    else{
                        DatR[i][j][k] = DaR[i][j][k];
                        DatI[i][j][k] = DaI[i][j][k];
                    }
                }
            }
        }
        
        //row wise fft
        for (int i = 0; i < 4; i ++) {
            for (int j = 0; j < 4; j ++) {
                float tmpRowR[4];
                float tmpRowI[4];
                
                //collect a row
                for (int k = 0; k < 4; k ++) {
                    // throw into a tmp array to do FFT upon
                    tmpRowR[k] = DatR[i][j][k];
                    tmpRowI[k] = DatI[i][j][k];
                }
                
                float4 tmpRowRFF;
                tmpRowRFF.x = tmpRowR[0];
                tmpRowRFF.y = tmpRowR[1];
                tmpRowRFF.z = tmpRowR[2];
                tmpRowRFF.w = tmpRowR[3];
                
                float4 tmpRowIFF;
                tmpRowIFF.x = tmpRowI[0];
                tmpRowIFF.y = tmpRowI[1];
                tmpRowIFF.z = tmpRowI[2];
                tmpRowIFF.w = tmpRowI[3];
        
                
                //apply FFT
                #ifdef FastFourierTransform
                float8 Out = FFT(FFT_FORWARD, 2, tmpRowRFF, tmpRowIFF);
                #else
                float8 Out = DFT(FFT_FORWARD, 4, tmpRowRFF, tmpRowIFF);
                #endif
                
                tmpRowR[0] = Out.s0;
                tmpRowR[1] = Out.s1;
                tmpRowR[2] = Out.s2;
                tmpRowR[3] = Out.s3;
                
                tmpRowI[0] = Out.s4;
                tmpRowI[1] = Out.s5;
                tmpRowI[2] = Out.s6;
                tmpRowI[3] = Out.s7;
                
                // store the resulting row into original array
                for (int k = 0; k < 4; k ++) {
                    // throw into a tmp array to do FFT upon
                    DatR[i][j][k] = tmpRowR[k];
                    DatI[i][j][k] = tmpRowI[k];
                }
            }
        }
        
        
        //column wise fft
        for (int i = 0; i < 4; i ++) {
            for (int k = 0; k < 4; k ++) {
                
                float tmpColR[4];
                float tmpColI[4];
                                
                for (int j = 0; j < 4; j ++) {
                    // throw into a tmp array to do FFT upon
                    tmpColR[j] = DatR[i][j][k];
                    tmpColI[j] = DatI[i][j][k];
                }
                
                float4 tmpColRFF;
                tmpColRFF.x = tmpColR[0];
                tmpColRFF.y = tmpColR[1];
                tmpColRFF.z = tmpColR[2];
                tmpColRFF.w = tmpColR[3];
                
                float4 tmpColIFF;
                tmpColIFF.x = tmpColI[0];
                tmpColIFF.y = tmpColI[1];
                tmpColIFF.z = tmpColI[2];
                tmpColIFF.w = tmpColI[3];
                
                #ifdef FastFourierTransform
                float8 Out = FFT(FFT_FORWARD, 2, tmpColRFF, tmpColIFF);
                #else
                float8 Out = DFT(FFT_FORWARD, 4, tmpColRFF, tmpColIFF);
                #endif

                tmpColR[0] = Out.s0;
                tmpColR[1] = Out.s1;
                tmpColR[2] = Out.s2;
                tmpColR[3] = Out.s3;
                
                tmpColI[0] = Out.s4;
                tmpColI[1] = Out.s5;
                tmpColI[2] = Out.s6;
                tmpColI[3] = Out.s7;
                
                for (int j = 0; j < 4; j ++) {
                    // throw into a tmp array to do FFT upon
                    DatR[i][j][k] = tmpColR[j];
                    DatI[i][j][k] = tmpColI[j];
                }
            }
        }
        

        //slice wise fft
        for (int j = 0; j < 4; j ++) {
            for (int k = 0; k < 4; k ++) {
                float tmpSliR[4];
                float tmpSliI[4];
                
                //throw present slice into a tmp array to do FFT upon
                for (int i = 0; i < 4; i ++) {
                    tmpSliR[i] = DatR[i][j][k];
                    tmpSliI[i] = DatI[i][j][k];
                }
                
                float4 tmpSliRFF;
                tmpSliRFF.x = tmpSliR[0];
                tmpSliRFF.y = tmpSliR[1];
                tmpSliRFF.z = tmpSliR[2];
                tmpSliRFF.w = tmpSliR[3];
                
                float4 tmpSliIFF;
                tmpSliIFF.x = tmpSliI[0];
                tmpSliIFF.y = tmpSliI[1];
                tmpSliIFF.z = tmpSliI[2];
                tmpSliIFF.w = tmpSliI[3];
                
                #ifdef FastFourierTransform
                float8 Out = FFT(FFT_FORWARD, 2, tmpSliRFF, tmpSliIFF);
                #else
                float8 Out = DFT(FFT_FORWARD, 4, tmpSliRFF, tmpSliIFF);
                #endif
                
                tmpSliR[0] = Out.s0;
                tmpSliR[1] = Out.s1;
                tmpSliR[2] = Out.s2;
                tmpSliR[3] = Out.s3;
                
                tmpSliI[0] = Out.s4;
                tmpSliI[1] = Out.s5;
                tmpSliI[2] = Out.s6;
                tmpSliI[3] = Out.s7;    
                
                //collect present slice into original 4*4*4 array
                for (int i = 0; i < 4; i ++) {
                    DatR[i][j][k] = tmpSliR[i];
                    DatI[i][j][k] = tmpSliI[i];
                }
            }
        }


        // ------------------------> Divide Da by (3*3*3) denoted Dk <------------------------ 
        for (int i = 0; i < 4; i ++) {
            for (int j = 0; j < 4; j ++) {
                for (int k = 0; k < 4; k ++) {
                    DatR[i][j][k] = DatR[i][j][k] / (4*4*4);
                    DatI[i][j][k] = DatI[i][j][k] / (4*4*4);
                }
            }
        }
        
        
        
        //convolution 
        //generate the kernel
        //(Sobel Power Filter Bank)
        float DkR[4][4][4];
        float DkI[4][4][4];
        
        float filtX[3] = {-1, 0, 1};
        float filtY[3] = {-1, 0, 1};
        float filtZ[3] = {-1, 0, 1};
        
        for (int i = 0; i < 4; i ++) {
            for (int j = 0; j < 4; j ++) {
                for (int k = 0; k < 4; k++) {
                    if (i == 3 || j == 3 || k == 3) {
                        DkR[i][j][k] = 0;
                    }
                    else {
                        DkR[i][j][k] = - pow(filtX[i],5) * pow(filtY[j], 2) * pow(filtZ[k], 2) * exp(-(pow(filtX[i],2)+pow(filtY[j],2)+pow(filtZ[k],2))/3);                        
                    }
                    DkI[i][j][k] = 0;
                }
            }
        }
        
        //Apply forward transform upon filter
        //First x-wise
        for (int i = 0; i < 4; i ++) {
            for (int j = 0; j < 4; j ++) {
                float tmpRowR[4];
                float tmpRowI[4];
                
                //collect a row
                for (int k = 0; k < 4; k ++) {
                    // throw into a tmp array to do FFT upon
                    tmpRowR[k] = DkR[i][j][k];
                    tmpRowI[k] = DkI[i][j][k];
                }
                
                float4 tmpRowRFF;
                tmpRowRFF.x = tmpRowR[0];
                tmpRowRFF.y = tmpRowR[1];
                tmpRowRFF.z = tmpRowR[2];
                tmpRowRFF.w = tmpRowR[3];
                
                float4 tmpRowIFF;
                tmpRowIFF.x = tmpRowI[0];
                tmpRowIFF.y = tmpRowI[1];
                tmpRowIFF.z = tmpRowI[2];
                tmpRowIFF.w = tmpRowI[3];
                
                
                //apply FFT
                #ifdef FastFourierTransform
                float8 Out = FFT(FFT_FORWARD, 2, tmpRowRFF, tmpRowIFF);
                #else
                float8 Out = DFT(FFT_FORWARD, 4, tmpRowRFF, tmpRowIFF);
                #endif
                
                tmpRowR[0] = Out.s0;
                tmpRowR[1] = Out.s1;
                tmpRowR[2] = Out.s2;
                tmpRowR[3] = Out.s3;
                
                tmpRowI[0] = Out.s4;
                tmpRowI[1] = Out.s5;
                tmpRowI[2] = Out.s6;
                tmpRowI[3] = Out.s7;
                
                // store the resulting row into original array
                for (int k = 0; k < 4; k ++) {
                    // throw into a tmp array to do FFT upon
                    DkR[i][j][k] = tmpRowR[k];
                    DkI[i][j][k] = tmpRowI[k];
                }
            }
        }

        //Then y-wise
        for (int i = 0; i < 4; i ++) {
            for (int k = 0; k < 4; k ++) {
                
                float tmpColR[4];
                float tmpColI[4];
                
                for (int j = 0; j < 4; j ++) {
                    // throw into a tmp array to do FFT upon
                    tmpColR[j] = DkR[i][j][k];
                    tmpColI[j] = DkI[i][j][k];
                }
                
                float4 tmpColRFF;
                tmpColRFF.x = tmpColR[0];
                tmpColRFF.y = tmpColR[1];
                tmpColRFF.z = tmpColR[2];
                tmpColRFF.w = tmpColR[3];
                
                float4 tmpColIFF;
                tmpColIFF.x = tmpColI[0];
                tmpColIFF.y = tmpColI[1];
                tmpColIFF.z = tmpColI[2];
                tmpColIFF.w = tmpColI[3];
                
                #ifdef FastFourierTransform
                float8 Out = FFT(FFT_FORWARD, 2, tmpColRFF, tmpColIFF);
                #else
                float8 Out = DFT(FFT_FORWARD, 4, tmpColRFF, tmpColIFF);
                #endif
                
                tmpColR[0] = Out.s0;
                tmpColR[1] = Out.s1;
                tmpColR[2] = Out.s2;
                tmpColR[3] = Out.s3;
                
                tmpColI[0] = Out.s4;
                tmpColI[1] = Out.s5;
                tmpColI[2] = Out.s6;
                tmpColI[3] = Out.s7;
                
                for (int j = 0; j < 4; j ++) {
                    // throw into a tmp array to do FFT upon
                    DkR[i][j][k] = tmpColR[j];
                    DkI[i][j][k] = tmpColI[j];
                }
            }
        }
        
        //Then z-wise
        for (int j = 0; j < 4; j ++) {
            for (int k = 0; k < 4; k ++) {
                float tmpSliR[4];
                float tmpSliI[4];
                
                //throw present slice into a tmp array to do FFT upon
                for (int i = 0; i < 4; i ++) {
                    tmpSliR[i] = DkR[i][j][k];
                    tmpSliI[i] = DkI[i][j][k];
                }
                
                float4 tmpSliRFF;
                tmpSliRFF.x = tmpSliR[0];
                tmpSliRFF.y = tmpSliR[1];
                tmpSliRFF.z = tmpSliR[2];
                tmpSliRFF.w = tmpSliR[3];
                
                float4 tmpSliIFF;
                tmpSliIFF.x = tmpSliI[0];
                tmpSliIFF.y = tmpSliI[1];
                tmpSliIFF.z = tmpSliI[2];
                tmpSliIFF.w = tmpSliI[3];
                
                #ifdef FastFourierTransform
                float8 Out = FFT(FFT_FORWARD, 2, tmpSliRFF, tmpSliIFF);
                #else
                float8 Out = DFT(FFT_FORWARD, 4, tmpSliRFF, tmpSliIFF);
                #endif
                
                tmpSliR[0] = Out.s0;
                tmpSliR[1] = Out.s1;
                tmpSliR[2] = Out.s2;
                tmpSliR[3] = Out.s3;
                
                tmpSliI[0] = Out.s4;
                tmpSliI[1] = Out.s5;
                tmpSliI[2] = Out.s6;
                tmpSliI[3] = Out.s7;    
                
                //collect present slice into original 4*4*4 array
                for (int i = 0; i < 4; i ++) {
                    DkR[i][j][k] = tmpSliR[i];
                    DkI[i][j][k] = tmpSliI[i];
                }
            }
        }

        //apply convolution
        // ------------------------> Divide Dk by (3*3*3) denoted Dk <------------------------ 
        for (int i = 0; i < 4; i ++) {
            for (int j = 0; j < 4; j ++) {
                for (int k = 0; k < 4; k ++) {
                    DkR[i][j][k] = DkR[i][j][k] / (4*4*4);
                    DkI[i][j][k] = DkI[i][j][k] / (4*4*4);
                }
            }
        }
        
        // ------------------------> Take the complex conjugate of Da <---------------------------
        for (int i = 0; i < 3; i ++) {
            for (int j = 0; j < 3; j ++) {
                for (int k = 0; k < 3; k ++) {
                    DatI[i][j][k] = -DatI[i][j][k];
                }
            }
        }
        
        // ------------------------> (Convolution) Multiply Da conjugate by Dk <-------------
        for (int i = 0; i < 3; i ++) {
            for (int j = 0; j < 3; j ++) {
                for (int k = 0; k < 3; k ++) {
                    DatR[i][j][k] = DatR[i][j][k] * DkR[i][j][k];
                    DatI[i][j][k] = DatI[i][j][k] * DkI[i][j][k];
                }
            }
        }
        //end of convolution
        
        
        
        //inverse transformation
        //First z-wise (slice)
        for (int j = 0; j < 4; j ++) {
            for (int k = 0; k < 4; k ++) {
                float tmpSliR[4];
                float tmpSliI[4];
                
                //throw present slice into a tmp array to do FFT upon
                for (int i = 0; i < 4; i ++) {
                    tmpSliR[i] = DatR[i][j][k];
                    tmpSliI[i] = DatI[i][j][k];
                }
                
                float4 tmpSliRFF;
                tmpSliRFF.x = tmpSliR[0];
                tmpSliRFF.y = tmpSliR[1];
                tmpSliRFF.z = tmpSliR[2];
                tmpSliRFF.w = tmpSliR[3];
                
                float4 tmpSliIFF;
                tmpSliIFF.x = tmpSliI[0];
                tmpSliIFF.y = tmpSliI[1];
                tmpSliIFF.z = tmpSliI[2];
                tmpSliIFF.w = tmpSliI[3];
                
                #ifdef FastFourierTransform
                float8 Out = FFT(FFT_REVERSE, 2, tmpSliRFF, tmpSliIFF);
                #else
                float8 Out = DFT(FFT_REVERSE, 4, tmpSliRFF, tmpSliIFF);
                #endif
                
                tmpSliR[0] = Out.s0;
                tmpSliR[1] = Out.s1;
                tmpSliR[2] = Out.s2;
                tmpSliR[3] = Out.s3;
                
                tmpSliI[0] = Out.s4;
                tmpSliI[1] = Out.s5;
                tmpSliI[2] = Out.s6;
                tmpSliI[3] = Out.s7;    
                
                //collect present slice into original 4*4*4 array
                for (int i = 0; i < 4; i ++) {
                    DatR[i][j][k] = tmpSliR[i];
                    DatI[i][j][k] = tmpSliI[i];
                }
            }
        }
        
        //Then y-wise (column wise inverse fft)
        for (int i = 0; i < 4; i ++) {
            for (int k = 0; k < 4; k ++) {
                
                float tmpColR[4];
                float tmpColI[4];
                
                for (int j = 0; j < 4; j ++) {
                    // throw into a tmp array to do FFT upon
                    tmpColR[j] = DatR[i][j][k];
                    tmpColI[j] = DatI[i][j][k];
                }
                
                float4 tmpColRFF;
                tmpColRFF.x = tmpColR[0];
                tmpColRFF.y = tmpColR[1];
                tmpColRFF.z = tmpColR[2];
                tmpColRFF.w = tmpColR[3];
                
                float4 tmpColIFF;
                tmpColIFF.x = tmpColI[0];
                tmpColIFF.y = tmpColI[1];
                tmpColIFF.z = tmpColI[2];
                tmpColIFF.w = tmpColI[3];
                
                #ifdef FastFourierTransform
                float8 Out = FFT(FFT_REVERSE, 2, tmpColRFF, tmpColIFF);
                #else
                float8 Out = DFT(FFT_REVERSE, 4, tmpColRFF, tmpColIFF);
                #endif
                
                tmpColR[0] = Out.s0;
                tmpColR[1] = Out.s1;
                tmpColR[2] = Out.s2;
                tmpColR[3] = Out.s3;
                
                tmpColI[0] = Out.s4;
                tmpColI[1] = Out.s5;
                tmpColI[2] = Out.s6;
                tmpColI[3] = Out.s7;
                
                for (int j = 0; j < 4; j ++) {
                    // throw into a tmp array to do FFT upon
                    DatR[i][j][k] = tmpColR[j];
                    DatI[i][j][k] = tmpColI[j];
                }
            }
        }

        //Finally x-wise (row wise inv fft)
        for (int i = 0; i < 4; i ++) {
            for (int j = 0; j < 4; j ++) {
                float tmpRowR[4];
                float tmpRowI[4];
                
                //collect a row
                for (int k = 0; k < 4; k ++) {
                    // throw into a tmp array to do FFT upon
                    tmpRowR[k] = DatR[i][j][k];
                    tmpRowI[k] = DatI[i][j][k];
                }
                
                float4 tmpRowRFF;
                tmpRowRFF.x = tmpRowR[0];
                tmpRowRFF.y = tmpRowR[1];
                tmpRowRFF.z = tmpRowR[2];
                tmpRowRFF.w = tmpRowR[3];
                
                float4 tmpRowIFF;
                tmpRowIFF.x = tmpRowI[0];
                tmpRowIFF.y = tmpRowI[1];
                tmpRowIFF.z = tmpRowI[2];
                tmpRowIFF.w = tmpRowI[3];
                
                
                //apply FFT
                #ifdef FastFourierTransform
                float8 Out = FFT(FFT_REVERSE, 2, tmpRowRFF, tmpRowIFF);
                #else
                float8 Out = DFT(FFT_REVERSE, 4, tmpRowRFF, tmpRowIFF);
                #endif
                
                tmpRowR[0] = Out.s0;
                tmpRowR[1] = Out.s1;
                tmpRowR[2] = Out.s2;
                tmpRowR[3] = Out.s3;
                
                tmpRowI[0] = Out.s4;
                tmpRowI[1] = Out.s5;
                tmpRowI[2] = Out.s6;
                tmpRowI[3] = Out.s7;
                
                // store the resulting row into original array
                for (int k = 0; k < 4; k ++) {
                    // throw into a tmp array to do FFT upon
                    DatR[i][j][k] = tmpRowR[k];
                    DatI[i][j][k] = tmpRowI[k];
                }
            }
        }

        // ------------------------> Multiply Da by (3*3*3) denoted Da' <------------------------ 
        for (int i = 0; i < 4; i ++) {
            for (int j = 0; j < 4; j ++) {
                for (int k = 0; k < 4; k ++) {
                    DatR[i][j][k] = DatR[i][j][k] * (4*4*4);
                    DatI[i][j][k] = DatI[i][j][k] * (4*4*4);
                }
            }
        }
        
        //populate back into a non dyadic matrix (3*3*3)
        for(int i = 0; i < 4; i++){
            for(int j = 0; j < 4; j++){
                for(int k = 0; k < 4; k++){
                    if (k != 3 && j != 3 && i != 3) {
                        DaR[i][j][k] = DatR[i][j][k];
                        DaI[i][j][k] = DatI[i][j][k];
                    }
                }
            }
        }
            
        if(c == 0){
            for (int i = 0; i < 3; i ++) {
                for (int j = 0; j < 3; j ++) {
                    for (int k = 0; k < 3; k ++) {
                        WriteDaR[i][j][k].x = DaR[i][j][k];
                        WriteDaI[i][j][k].x = DaI[i][j][k];
                    }
                }
            }
        }
        else if(c == 1){
            for (int i = 0; i < 3; i ++) {
                for (int j = 0; j < 3; j ++) {
                    for (int k = 0; k < 3; k ++) {
                        WriteDaR[i][j][k].y = DaR[i][j][k];
                        WriteDaI[i][j][k].y = DaI[i][j][k];
                    }
                }
            }
        }
        else{
            for (int i = 0; i < 3; i ++) {
                for (int j = 0; j < 3; j ++) {
                    for (int k = 0; k < 3; k ++) {
                        WriteDaR[i][j][k].z = DaR[i][j][k];
                        WriteDaI[i][j][k].z = DaI[i][j][k];
                    }
                }
            }
        }
    
            
        }

        
        //write this channel out
        for(int z = startImageCoord.z; z <= endImageCoord.z; z++){
            for(int y = startImageCoord.y; y <= endImageCoord.y; y++){
                for(int x= startImageCoord.x; x <= endImageCoord.x; x++){
                    #ifdef VolumetricRendering
                    if(WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x > 0.05f && WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y > 0.05f && WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z > 0.05f){
                        write_imagef(dstImg, (int4)(x,y,z,1),(float4)(WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z,1)); 
                        //write_imagef(dstImg, outImageCoord, (float4)(WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z,1));
                    }
                    #else
                    //output over these output coordinates
                    write_imagef(dstImg, (int4)(x,y,z,1),(float4)(WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z,1)); 
                    #endif
                }
            }
        }
    }
}


__kernel
void sobel3DCPU(__read_only image3d_t srcImg,
             __write_only image3d_t dstImg,
             sampler_t sampler,
             int width, int height, int depth)
{    
    
    int x = get_group_id(0) + get_local_id(0);
    int y = get_group_id(1) + get_local_id(1);
    int z = get_group_id(2) + get_local_id(2);
    
    if(x%3 != 0 || y%3 != 0 || z%3 != 0){
        return;
    }
    //if its out of bounds why bother?
    //if (x >= get_image_width(srcImg) || y >= get_image_height(srcImg) || z >= get_image_depth(srcImg)){
    //    return;
    //}
    
    //w is ignored? I believe w is included as all data types are a power of 2
    int4 startImageCoord = (int4) (x - 1,
                                   y - 1,
                                   z - 1, 
                                   1);
    
    int4 endImageCoord   = (int4) (x + 1,
                                   y + 1, 
                                   //remove plus 1 to get indexing proper
                                   z + 1 /* + 1*/, 
                                   1);
    
    int4 outImageCoord = (int4) (x,
                                 y,
                                 z, 
                                 1);
    
    if (outImageCoord.x < width && outImageCoord.y < height && outImageCoord.z < depth)
    {
        float4 thisIn = (float4)(0.0f, 0.0f, 0.0f, 0.0f);
        
        //        long thisDepth = endImageCoord.z - startImageCoord.z;
        //        long thisHeight = endImageCoord.y - startImageCoord.y;
        //        long thisWidth = endImageCoord.x - startImageCoord.x;
        //printf((char const *)"%i", (int)thisDepth);
        //int stackSize = thisDepth*thisWidth*thisHeight;
        
        
        float DaR[3][3][3];
        float DaI[3][3][3];
        
        float4 WriteDaR[3][3][3];
        float4 WriteDaI[3][3][3];
        
        
        for(int c = 0; c < 3; c++){
            //first collect the red channel, then green than blue
            for(int z = startImageCoord.z; z <= endImageCoord.z; z++){
                for(int y = startImageCoord.y; y <= endImageCoord.y; y++){
                    for(int x = startImageCoord.x; x <= endImageCoord.x; x++){
                        thisIn = read_imagef(srcImg, sampler, (int4)(x,y,z,1));
                        if(c == 0){
                            DaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = thisIn.x;
                        }
                        else if(c == 1){
                            DaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = thisIn.y; 
                        }
                        else{
                            DaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = thisIn.z;
                        }
                        DaI[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = 0.0f;
                    }
                }
            }
            
            float DatR[4][4][4];
            float DatI[4][4][4];
            
            
            //set out 4 window size (need 3 for correct filter focus, however need to be dyadic for fft, solution use window 
            //size of 4*4*4 whilst only populating the 3*3*3 and padding the rest with zeros)
            for(int i = 0; i < 4; i++){
                for(int j = 0; j < 4; j++){
                    for(int k = 0; k < 4; k++){
                        if (k == 3 || j == 3 || i == 3) {
                            DatR[i][j][k] = 0;
                            DatI[i][j][k] = 0;
                        }
                        else{
                            DatR[i][j][k] = DaR[i][j][k];
                            DatI[i][j][k] = DaI[i][j][k];
                        }
                    }
                }
            }
            
            //row wise fft
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    float tmpRowR[4];
                    float tmpRowI[4];
                    
                    //collect a row
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        tmpRowR[k] = DatR[i][j][k];
                        tmpRowI[k] = DatI[i][j][k];
                    }
                    
                    //apply FFT
                    #ifdef FastFourierTransform
                    FFTCPU(FFT_FORWARD, 2, tmpRowR, tmpRowI);
                    #else
                    DFTCPU(FFT_FORWARD, 4, tmpRowR, tmpRowI);
                    #endif
                    
                    // store the resulting row into original array
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        DatR[i][j][k] = tmpRowR[k];
                        DatI[i][j][k] = tmpRowI[k];
                    }
                }
            }
            
            
            //column wise fft
            for (int i = 0; i < 4; i ++) {
                for (int k = 0; k < 4; k ++) {
                    
                    float tmpColR[4];
                    float tmpColI[4];
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        tmpColR[j] = DatR[i][j][k];
                        tmpColI[j] = DatI[i][j][k];
                    }
                    
                    #ifdef FastFourierTransform
                    FFTCPU(FFT_FORWARD, 2, tmpColR, tmpColI);
                    #else
                    DFTCPU(FFT_FORWARD, 4, tmpColR, tmpColI);
                    #endif
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        DatR[i][j][k] = tmpColR[j];
                        DatI[i][j][k] = tmpColI[j];
                    }
                }
            }
            
            //slice wise fft
            for (int j = 0; j < 4; j ++) {
                for (int k = 0; k < 4; k ++) {
                    float tmpSliR[4];
                    float tmpSliI[4];
                    
                    //throw present slice into a tmp array to do FFT upon
                    for (int i = 0; i < 4; i ++) {
                        tmpSliR[i] = DatR[i][j][k];
                        tmpSliI[i] = DatI[i][j][k];
                    }
                                        
                    #ifdef FastFourierTransform
                    FFTCPU(FFT_FORWARD, 2, tmpSliR, tmpSliI);
                    #else
                    DFTCPU(FFT_FORWARD, 4, tmpSliR, tmpSliI);
                    #endif
                    
                    //collect present slice into original 4*4*4 array
                    for (int i = 0; i < 4; i ++) {
                        DatR[i][j][k] = tmpSliR[i];
                        DatI[i][j][k] = tmpSliI[i];
                    }
                }
            }
            
            
            // ------------------------> Divide Da by (3*3*3) denoted Dk <------------------------ 
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    for (int k = 0; k < 4; k ++) {
                        DatR[i][j][k] = DatR[i][j][k] / (4*4*4);
                        DatI[i][j][k] = DatI[i][j][k] / (4*4*4);
                    }
                }
            }
            
            
            
            //convolution 
            //generate the kernel
            //(Sobel Power Filter Bank)
            float DkR[4][4][4];
            float DkI[4][4][4];
            
            float filtX[3] = {-1, 0, 1};
            float filtY[3] = {-1, 0, 1};
            float filtZ[3] = {-1, 0, 1};
            
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    for (int k = 0; k < 4; k++) {
                        if (i == 3 || j == 3 || k == 3) {
                            DkR[i][j][k] = 0;
                        }
                        else {
                            DkR[i][j][k] = - pow(filtX[i],5) * pow(filtY[j], 2) * pow(filtZ[k], 2) * exp(-(pow(filtX[i],2)+pow(filtY[j],2)+pow(filtZ[k],2))/3);                        
                        }
                        DkI[i][j][k] = 0;
                    }
                }
            }
            
            //check filter coefficients
            //      if(outImageCoord.x == 6 && outImageCoord.y == 6 && outImageCoord.z == 6){
            //            for (int i = 0; i < 3; i ++) {
            //                for (int j = 0; j < 3; j ++) {
            //                    for (int k = 0; k < 3; k++) {
            //                        printf((const char*)"at index[%i][%i][%i] -> %f\n",i,j,k, DkR[i][j][k]);
            //                    }
            //                }
            //            }
            //      }
            
            //Apply forward transform upon filter
            //First x-wise
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    float tmpRowR[4];
                    float tmpRowI[4];
                    
                    //collect a row
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        tmpRowR[k] = DkR[i][j][k];
                        tmpRowI[k] = DkI[i][j][k];
                    }
                    
                    //apply FFT
                    #ifdef FastFourierTransform
                    FFTCPU(FFT_FORWARD, 2, tmpRowR, tmpRowI);
                    #else
                    DFTCPU(FFT_FORWARD, 4, tmpRowR, tmpRowI);
                    #endif
                    
                    // store the resulting row into original array
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        DkR[i][j][k] = tmpRowR[k];
                        DkI[i][j][k] = tmpRowI[k];
                    }
                }
            }
            
            //Then y-wise
            for (int i = 0; i < 4; i ++) {
                for (int k = 0; k < 4; k ++) {
                    
                    float tmpColR[4];
                    float tmpColI[4];
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        tmpColR[j] = DkR[i][j][k];
                        tmpColI[j] = DkI[i][j][k];
                    }
                                        
                    #ifdef FastFourierTransform
                    FFTCPU(FFT_FORWARD, 2, tmpColR, tmpColI);
                    #else
                    DFTCPU(FFT_FORWARD, 4, tmpColR, tmpColI);
                    #endif
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        DkR[i][j][k] = tmpColR[j];
                        DkI[i][j][k] = tmpColI[j];
                    }
                }
            }
            
            //Then z-wise
            for (int j = 0; j < 4; j ++) {
                for (int k = 0; k < 4; k ++) {
                    float tmpSliR[4];
                    float tmpSliI[4];
                    
                    //throw present slice into a tmp array to do FFT upon
                    for (int i = 0; i < 4; i ++) {
                        tmpSliR[i] = DkR[i][j][k];
                        tmpSliI[i] = DkI[i][j][k];
                    }
                                        
                    #ifdef FastFourierTransform
                    FFTCPU(FFT_FORWARD, 2, tmpSliR, tmpSliI);
                    #else
                    DFTCPU(FFT_FORWARD, 4, tmpSliR, tmpSliI);
                    #endif  
                    
                    //collect present slice into original 4*4*4 array
                    for (int i = 0; i < 4; i ++) {
                        DkR[i][j][k] = tmpSliR[i];
                        DkI[i][j][k] = tmpSliI[i];
                    }
                }
            }
            
            //apply convolution
            // ------------------------> Divide Dk by (3*3*3) denoted Dk <------------------------ 
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    for (int k = 0; k < 4; k ++) {
                        DkR[i][j][k] = DkR[i][j][k] / (4*4*4);
                        DkI[i][j][k] = DkI[i][j][k] / (4*4*4);
                    }
                }
            }
            
            // ------------------------> Take the complex conjugate of Da <---------------------------
            for (int i = 0; i < 3; i ++) {
                for (int j = 0; j < 3; j ++) {
                    for (int k = 0; k < 3; k ++) {
                        DatI[i][j][k] = -DatI[i][j][k];
                    }
                }
            }
            
            // ------------------------> (Convolution) Multiply Da conjugate by Dk <-------------
            for (int i = 0; i < 3; i ++) {
                for (int j = 0; j < 3; j ++) {
                    for (int k = 0; k < 3; k ++) {
                        DatR[i][j][k] = DatR[i][j][k] * DkR[i][j][k];
                        DatI[i][j][k] = DatI[i][j][k] * DkI[i][j][k];
                    }
                }
            }
            //end of convolution
            
            
            
            //inverse transformation
            //First z-wise (slice)
            for (int j = 0; j < 4; j ++) {
                for (int k = 0; k < 4; k ++) {
                    float tmpSliR[4];
                    float tmpSliI[4];
                    
                    //throw present slice into a tmp array to do FFT upon
                    for (int i = 0; i < 4; i ++) {
                        tmpSliR[i] = DatR[i][j][k];
                        tmpSliI[i] = DatI[i][j][k];
                    }
                                        
                    #ifdef FastFourierTransform
                    FFTCPU(FFT_REVERSE, 2, tmpSliR, tmpSliI);
                    #else
                    DFTCPU(FFT_REVERSE, 4, tmpSliR, tmpSliI);
                    #endif
                    
                    //collect present slice into original 4*4*4 array
                    for (int i = 0; i < 4; i ++) {
                        DatR[i][j][k] = tmpSliR[i];
                        DatI[i][j][k] = tmpSliI[i];
                    }
                }
            }
            
            //Then y-wise (column wise inverse fft)
            for (int i = 0; i < 4; i ++) {
                for (int k = 0; k < 4; k ++) {
                    
                    float tmpColR[4];
                    float tmpColI[4];
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        tmpColR[j] = DatR[i][j][k];
                        tmpColI[j] = DatI[i][j][k];
                    }
                    
                    #ifdef FastFourierTransform
                    FFTCPU(FFT_REVERSE, 2, tmpColR, tmpColI);
                    #else
                    DFTCPU(FFT_REVERSE, 4, tmpColR, tmpColI);
                    #endif
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        DatR[i][j][k] = tmpColR[j];
                        DatI[i][j][k] = tmpColI[j];
                    }
                }
            }
            
            //Finally x-wise (row wise inv fft)
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    float tmpRowR[4];
                    float tmpRowI[4];
                    
                    //collect a row
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        tmpRowR[k] = DatR[i][j][k];
                        tmpRowI[k] = DatI[i][j][k];
                    }
                    
                    //apply FFT
                    #ifdef FastFourierTransform
                    FFTCPU(FFT_REVERSE, 2, tmpRowR, tmpRowI);
                    #else
                    DFTCPU(FFT_REVERSE, 4, tmpRowR, tmpRowI);
                    #endif
                    
                    // store the resulting row into original array
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        DatR[i][j][k] = tmpRowR[k];
                        DatI[i][j][k] = tmpRowI[k];
                    }
                }
            }
            
            // ------------------------> Multiply Da by (3*3*3) denoted Da' <------------------------ 
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    for (int k = 0; k < 4; k ++) {
                        DatR[i][j][k] = DatR[i][j][k] * (4*4*4);
                        DatI[i][j][k] = DatI[i][j][k] * (4*4*4);
                    }
                }
            }
            
            //populate back into a non dyadic matrix (3*3*3)
            for(int i = 0; i < 4; i++){
                for(int j = 0; j < 4; j++){
                    for(int k = 0; k < 4; k++){
                        if (k != 3 && j != 3 && i != 3) {
                            DaR[i][j][k] = DatR[i][j][k];
                            DaI[i][j][k] = DatI[i][j][k];
                        }
                    }
                }
            }
            
            if(c == 0){
                for (int i = 0; i < 3; i ++) {
                    for (int j = 0; j < 3; j ++) {
                        for (int k = 0; k < 3; k ++) {
                            WriteDaR[i][j][k].x = DaR[i][j][k];
                            WriteDaI[i][j][k].x = DaI[i][j][k];
                        }
                    }
                }
            }
            else if(c == 1){
                for (int i = 0; i < 3; i ++) {
                    for (int j = 0; j < 3; j ++) {
                        for (int k = 0; k < 3; k ++) {
                            WriteDaR[i][j][k].y = DaR[i][j][k];
                            WriteDaI[i][j][k].y = DaI[i][j][k];
                        }
                    }
                }
            }
            else{
                for (int i = 0; i < 3; i ++) {
                    for (int j = 0; j < 3; j ++) {
                        for (int k = 0; k < 3; k ++) {
                            WriteDaR[i][j][k].z = DaR[i][j][k];
                            WriteDaI[i][j][k].z = DaI[i][j][k];
                        }
                    }
                }
            }
        }
        
        
        //write this channel out
        for(int z = startImageCoord.z; z <= endImageCoord.z; z++){
            for(int y = startImageCoord.y; y <= endImageCoord.y; y++){
                for(int x= startImageCoord.x; x <= endImageCoord.x; x++){
                    #ifdef VolumetricRendering
                    if(WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x > 0.05f && WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y > 0.05f && WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z > 0.05f){
                        //write_imagef(dstImg, outImageCoord, (float4)(WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z,1));
                        write_imagef(dstImg, (int4)(x,y,z,1),(float4)(WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z,1)); 
                    }
                    #else
                    write_imagef(dstImg, (int4)(x,y,z,1),(float4)(WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z,1)); 
                    //write_imagef(dstImg, outImageCoord, (float4)(WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z,1));
                    #endif
                }
            }
        }
    }
}

__kernel 
//__attribute__((reqd_work_group_size(256, 256, 1)))
void thresholdAndCopy(__read_only image3d_t srcImg,
                    __write_only image3d_t dstImg,
                    sampler_t sampler,
                    int width, int height, int depth)
{
    //w is ignored? I believe w is included as all data types are a power of 2
    int4 startImageCoord = (int4) (get_global_id(0) - 1,
                                   get_global_id(1) - 1,
                                   get_global_id(2) - 1, 
                                   1);
    
    int4 endImageCoord   = (int4) (get_global_id(0) + 1,
                                   get_global_id(1) + 1, 
                                   //removed plus 1 to get indexing proper
                                   get_global_id(2)/* + 1*/, 
                                   1);
    
    int4 outImageCoord = (int4) (get_global_id(0),
                                 get_global_id(1),
                                 get_global_id(2), 
                                 1);
    
    if (outImageCoord.x < width && outImageCoord.y < height && outImageCoord.z < depth)
    {
        float4 thisIn = (float4)(0.0f, 0.0f, 0.0f, 0.0f);
        
        //allocate spare buffer
        //float4 tmpBuffer[(endImageCoord.x*endImageCoord.y) - (startImageCoord.x*startImageCoord.y)];
        
        //int rowPitch = endImageCoord.x - startImageCoord.x;
        //int slicePitch = endImageCoord.y - startImageCoord.y;

        
        for(int z = startImageCoord.z; z <= endImageCoord.z; z++)
        {
            //The outer loop is used to process all slices
            
            //forward pass
            for(int y = startImageCoord.y; y <= endImageCoord.y; y++)
            {
                for(int x= startImageCoord.x; x <= endImageCoord.x; x++)
                {
                    
                    thisIn = read_imagef(srcImg, sampler, (int4)(x, y, z, 1));
                    
                    if(thisIn.x > 0.05 || thisIn.y > 0.05 || thisIn.z > 0.05){
                        write_imagef(dstImg, outImageCoord, thisIn);
                    }
                }
            }
            
            //backward pass
//            for(int y = endImageCoord.y; y > startImageCoord.y; y--)
//            {
//                for(int x= endImageCoord.x; x > startImageCoord.x; x--)
//                {
//                    
//                    thisIn = tmpBuffer[(y*rowPitch)+x];
//                    
//                    // Write the output value to image
//                    write_imagef(dstImg, outImageCoord, thisIn);
//                    
//                }
//            }
        }
    }
    
}

__kernel 
// kernel simply copies from input buffer to output
void straightCopy(__read_only image3d_t srcImg,
          __write_only image3d_t dstImg,
          sampler_t sampler,
          int width, int height, int depth)
{
    //w is ignored? I believe w is included as all data types are a power of 2
    int4 startImageCoord = (int4) (get_global_id(0) - 1,
                                   get_global_id(1) - 1,
                                   get_global_id(2) - 1, 
                                   1);
    
    int4 endImageCoord   = (int4) (get_global_id(0) + 1,
                                   get_global_id(1) + 1, 
                                   //removed plus 1 to get indexing proper
                                   get_global_id(2)/* + 1*/, 
                                   1);
    
    int4 outImageCoord = (int4) (get_global_id(0),
                                 get_global_id(1),
                                 get_global_id(2), 
                                 1);
    
    if (outImageCoord.x < width && outImageCoord.y < height && outImageCoord.z < depth){
        for(int z = startImageCoord.z; z <= endImageCoord.z; z++){
            for(int y = startImageCoord.y; y <= endImageCoord.y; y++){
                for(int x= startImageCoord.x; x <= endImageCoord.x; x++){
                    write_imagef(dstImg, outImageCoord, read_imagef(srcImg, sampler, (int4)(x, y, z, 1)));
                }
            }
        }
    }
    
}


/* --------------------------> Real work happens past this point <--------------------------------- */
__kernel
void sobel3DwInternalStructureEmphasis(__read_only image3d_t srcImg,
             __write_only image3d_t dstImg,
             sampler_t sampler,
             int width, int height, int depth)
{
    
    //    int x = (int)get_global_id(0);
    //    int y = (int)get_global_id(1);
    //    int z = (int)get_global_id(2);
    
    //this approach is needed for working with workgroups
    int x = get_group_id(0) + get_local_id(0);
    int y = get_group_id(1) + get_local_id(1);
    int z = get_group_id(2) + get_local_id(2);
    
    //3*3*3 window do computation on
    if(x%3 != 0 || y%3 != 0 || z%3 != 0){
        return;
    }
    
    //w is ignored? I believe w is included as all data types are a power of 2
    int4 startImageCoord = (int4) (x - 1,
                                   y - 1,
                                   z - 1, 
                                   1);
    
    int4 endImageCoord   = (int4) (x + 1,
                                   y + 1, 
                                   //remove plus 1 to get indexing proper
                                   z + 1 /* + 1*/, 
                                   1);
    
    int4 outImageCoord = (int4) (x,
                                 y,
                                 z, 
                                 1);
    
    if (outImageCoord.x < width && outImageCoord.y < height && outImageCoord.z < depth)
    {
        float4 thisIn = (float4)(0.0f, 0.0f, 0.0f, 0.0f);
        
        float DaR[3][3][3];
        float DaI[3][3][3];
        
        float4 WriteDaR[3][3][3];
        float4 WriteDaI[3][3][3];
        
        
        for(int c = 0; c < 3; c++){
            //first collect the red channel, then green than blue
            for(int z = startImageCoord.z; z <= endImageCoord.z; z++){
                for(int y = startImageCoord.y; y <= endImageCoord.y; y++){
                    for(int x = startImageCoord.x; x <= endImageCoord.x; x++){
                        thisIn = read_imagef(srcImg, sampler, (int4)(x,y,z,1));
                        if(c == 0){
                            DaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = thisIn.x;
                        }
                        else if(c == 1){
                            DaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = thisIn.y; 
                        }
                        else{
                            DaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = thisIn.z;
                        }
                        DaI[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x] = 0.0f;
                    }
                }
            }
            
            float DatR[4][4][4];
            float DatI[4][4][4];
            
            
            //set out 4 window size (need 3 for correct filter focus, however need to be dyadic for fft, solution use window 
            //size of 4*4*4 whilst only populating the 3*3*3 and padding the rest with zeros)
            for(int i = 0; i < 4; i++){
                for(int j = 0; j < 4; j++){
                    for(int k = 0; k < 4; k++){
                        if (k == 3 || j == 3 || i == 3) {
                            DatR[i][j][k] = 0;
                            DatI[i][j][k] = 0;
                        }
                        else{
                            DatR[i][j][k] = DaR[i][j][k];
                            DatI[i][j][k] = DaI[i][j][k];
                        }
                    }
                }
            }
            
            //row wise fft
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    float tmpRowR[4];
                    float tmpRowI[4];
                    
                    //collect a row
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        tmpRowR[k] = DatR[i][j][k];
                        tmpRowI[k] = DatI[i][j][k];
                    }
                    
                    float4 tmpRowRFF;
                    tmpRowRFF.x = tmpRowR[0];
                    tmpRowRFF.y = tmpRowR[1];
                    tmpRowRFF.z = tmpRowR[2];
                    tmpRowRFF.w = tmpRowR[3];
                    
                    float4 tmpRowIFF;
                    tmpRowIFF.x = tmpRowI[0];
                    tmpRowIFF.y = tmpRowI[1];
                    tmpRowIFF.z = tmpRowI[2];
                    tmpRowIFF.w = tmpRowI[3];
                    
                    
                    //apply FFT
#ifdef FastFourierTransform
                    float8 Out = FFT(FFT_FORWARD, 2, tmpRowRFF, tmpRowIFF);
#else
                    float8 Out = DFT(FFT_FORWARD, 4, tmpRowRFF, tmpRowIFF);
#endif
                    
                    tmpRowR[0] = Out.s0;
                    tmpRowR[1] = Out.s1;
                    tmpRowR[2] = Out.s2;
                    tmpRowR[3] = Out.s3;
                    
                    tmpRowI[0] = Out.s4;
                    tmpRowI[1] = Out.s5;
                    tmpRowI[2] = Out.s6;
                    tmpRowI[3] = Out.s7;
                    
                    // store the resulting row into original array
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        DatR[i][j][k] = tmpRowR[k];
                        DatI[i][j][k] = tmpRowI[k];
                    }
                }
            }
            
            
            //column wise fft
            for (int i = 0; i < 4; i ++) {
                for (int k = 0; k < 4; k ++) {
                    
                    float tmpColR[4];
                    float tmpColI[4];
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        tmpColR[j] = DatR[i][j][k];
                        tmpColI[j] = DatI[i][j][k];
                    }
                    
                    float4 tmpColRFF;
                    tmpColRFF.x = tmpColR[0];
                    tmpColRFF.y = tmpColR[1];
                    tmpColRFF.z = tmpColR[2];
                    tmpColRFF.w = tmpColR[3];
                    
                    float4 tmpColIFF;
                    tmpColIFF.x = tmpColI[0];
                    tmpColIFF.y = tmpColI[1];
                    tmpColIFF.z = tmpColI[2];
                    tmpColIFF.w = tmpColI[3];
                    
#ifdef FastFourierTransform
                    float8 Out = FFT(FFT_FORWARD, 2, tmpColRFF, tmpColIFF);
#else
                    float8 Out = DFT(FFT_FORWARD, 4, tmpColRFF, tmpColIFF);
#endif
                    
                    tmpColR[0] = Out.s0;
                    tmpColR[1] = Out.s1;
                    tmpColR[2] = Out.s2;
                    tmpColR[3] = Out.s3;
                    
                    tmpColI[0] = Out.s4;
                    tmpColI[1] = Out.s5;
                    tmpColI[2] = Out.s6;
                    tmpColI[3] = Out.s7;
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        DatR[i][j][k] = tmpColR[j];
                        DatI[i][j][k] = tmpColI[j];
                    }
                }
            }
            
            
            //slice wise fft
            for (int j = 0; j < 4; j ++) {
                for (int k = 0; k < 4; k ++) {
                    float tmpSliR[4];
                    float tmpSliI[4];
                    
                    //throw present slice into a tmp array to do FFT upon
                    for (int i = 0; i < 4; i ++) {
                        tmpSliR[i] = DatR[i][j][k];
                        tmpSliI[i] = DatI[i][j][k];
                    }
                    
                    float4 tmpSliRFF;
                    tmpSliRFF.x = tmpSliR[0];
                    tmpSliRFF.y = tmpSliR[1];
                    tmpSliRFF.z = tmpSliR[2];
                    tmpSliRFF.w = tmpSliR[3];
                    
                    float4 tmpSliIFF;
                    tmpSliIFF.x = tmpSliI[0];
                    tmpSliIFF.y = tmpSliI[1];
                    tmpSliIFF.z = tmpSliI[2];
                    tmpSliIFF.w = tmpSliI[3];
                    
#ifdef FastFourierTransform
                    float8 Out = FFT(FFT_FORWARD, 2, tmpSliRFF, tmpSliIFF);
#else
                    float8 Out = DFT(FFT_FORWARD, 4, tmpSliRFF, tmpSliIFF);
#endif
                    
                    tmpSliR[0] = Out.s0;
                    tmpSliR[1] = Out.s1;
                    tmpSliR[2] = Out.s2;
                    tmpSliR[3] = Out.s3;
                    
                    tmpSliI[0] = Out.s4;
                    tmpSliI[1] = Out.s5;
                    tmpSliI[2] = Out.s6;
                    tmpSliI[3] = Out.s7;    
                    
                    //collect present slice into original 4*4*4 array
                    for (int i = 0; i < 4; i ++) {
                        DatR[i][j][k] = tmpSliR[i];
                        DatI[i][j][k] = tmpSliI[i];
                    }
                }
            }
            
            
            // ------------------------> Divide Da by (3*3*3) denoted Dk <------------------------ 
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    for (int k = 0; k < 4; k ++) {
                        DatR[i][j][k] = DatR[i][j][k] / (4*4*4);
                        DatI[i][j][k] = DatI[i][j][k] / (4*4*4);
                    }
                }
            }
            
            
            
            //convolution 
            //generate the kernel
            //(Sobel Power Filter Bank)
            float DkR[4][4][4];
            float DkI[4][4][4];
            
            float filtX[3] = {-1, 0, 1};
            float filtY[3] = {-1, 0, 1};
            float filtZ[3] = {-1, 0, 1};
            
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    for (int k = 0; k < 4; k++) {
                        if (i == 3 || j == 3 || k == 3) {
                            DkR[i][j][k] = 0;
                        }
                        else {
                            DkR[i][j][k] = - pow(filtX[i],5) * pow(filtY[j], 2) * pow(filtZ[k], 2) * exp(-(pow(filtX[i],2)+pow(filtY[j],2)+pow(filtZ[k],2))/3);                        
                        }
                        DkI[i][j][k] = 0;
                    }
                }
            }
            
            //Apply forward transform upon filter
            //First x-wise
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    float tmpRowR[4];
                    float tmpRowI[4];
                    
                    //collect a row
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        tmpRowR[k] = DkR[i][j][k];
                        tmpRowI[k] = DkI[i][j][k];
                    }
                    
                    float4 tmpRowRFF;
                    tmpRowRFF.x = tmpRowR[0];
                    tmpRowRFF.y = tmpRowR[1];
                    tmpRowRFF.z = tmpRowR[2];
                    tmpRowRFF.w = tmpRowR[3];
                    
                    float4 tmpRowIFF;
                    tmpRowIFF.x = tmpRowI[0];
                    tmpRowIFF.y = tmpRowI[1];
                    tmpRowIFF.z = tmpRowI[2];
                    tmpRowIFF.w = tmpRowI[3];
                    
                    
                    //apply FFT
#ifdef FastFourierTransform
                    float8 Out = FFT(FFT_FORWARD, 2, tmpRowRFF, tmpRowIFF);
#else
                    float8 Out = DFT(FFT_FORWARD, 4, tmpRowRFF, tmpRowIFF);
#endif
                    
                    tmpRowR[0] = Out.s0;
                    tmpRowR[1] = Out.s1;
                    tmpRowR[2] = Out.s2;
                    tmpRowR[3] = Out.s3;
                    
                    tmpRowI[0] = Out.s4;
                    tmpRowI[1] = Out.s5;
                    tmpRowI[2] = Out.s6;
                    tmpRowI[3] = Out.s7;
                    
                    // store the resulting row into original array
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        DkR[i][j][k] = tmpRowR[k];
                        DkI[i][j][k] = tmpRowI[k];
                    }
                }
            }
            
            //Then y-wise
            for (int i = 0; i < 4; i ++) {
                for (int k = 0; k < 4; k ++) {
                    
                    float tmpColR[4];
                    float tmpColI[4];
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        tmpColR[j] = DkR[i][j][k];
                        tmpColI[j] = DkI[i][j][k];
                    }
                    
                    float4 tmpColRFF;
                    tmpColRFF.x = tmpColR[0];
                    tmpColRFF.y = tmpColR[1];
                    tmpColRFF.z = tmpColR[2];
                    tmpColRFF.w = tmpColR[3];
                    
                    float4 tmpColIFF;
                    tmpColIFF.x = tmpColI[0];
                    tmpColIFF.y = tmpColI[1];
                    tmpColIFF.z = tmpColI[2];
                    tmpColIFF.w = tmpColI[3];
                    
#ifdef FastFourierTransform
                    float8 Out = FFT(FFT_FORWARD, 2, tmpColRFF, tmpColIFF);
#else
                    float8 Out = DFT(FFT_FORWARD, 4, tmpColRFF, tmpColIFF);
#endif
                    
                    tmpColR[0] = Out.s0;
                    tmpColR[1] = Out.s1;
                    tmpColR[2] = Out.s2;
                    tmpColR[3] = Out.s3;
                    
                    tmpColI[0] = Out.s4;
                    tmpColI[1] = Out.s5;
                    tmpColI[2] = Out.s6;
                    tmpColI[3] = Out.s7;
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        DkR[i][j][k] = tmpColR[j];
                        DkI[i][j][k] = tmpColI[j];
                    }
                }
            }
            
            //Then z-wise
            for (int j = 0; j < 4; j ++) {
                for (int k = 0; k < 4; k ++) {
                    float tmpSliR[4];
                    float tmpSliI[4];
                    
                    //throw present slice into a tmp array to do FFT upon
                    for (int i = 0; i < 4; i ++) {
                        tmpSliR[i] = DkR[i][j][k];
                        tmpSliI[i] = DkI[i][j][k];
                    }
                    
                    float4 tmpSliRFF;
                    tmpSliRFF.x = tmpSliR[0];
                    tmpSliRFF.y = tmpSliR[1];
                    tmpSliRFF.z = tmpSliR[2];
                    tmpSliRFF.w = tmpSliR[3];
                    
                    float4 tmpSliIFF;
                    tmpSliIFF.x = tmpSliI[0];
                    tmpSliIFF.y = tmpSliI[1];
                    tmpSliIFF.z = tmpSliI[2];
                    tmpSliIFF.w = tmpSliI[3];
                    
#ifdef FastFourierTransform
                    float8 Out = FFT(FFT_FORWARD, 2, tmpSliRFF, tmpSliIFF);
#else
                    float8 Out = DFT(FFT_FORWARD, 4, tmpSliRFF, tmpSliIFF);
#endif
                    
                    tmpSliR[0] = Out.s0;
                    tmpSliR[1] = Out.s1;
                    tmpSliR[2] = Out.s2;
                    tmpSliR[3] = Out.s3;
                    
                    tmpSliI[0] = Out.s4;
                    tmpSliI[1] = Out.s5;
                    tmpSliI[2] = Out.s6;
                    tmpSliI[3] = Out.s7;    
                    
                    //collect present slice into original 4*4*4 array
                    for (int i = 0; i < 4; i ++) {
                        DkR[i][j][k] = tmpSliR[i];
                        DkI[i][j][k] = tmpSliI[i];
                    }
                }
            }
            
            //apply convolution
            // ------------------------> Divide Dk by (3*3*3) denoted Dk <------------------------ 
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    for (int k = 0; k < 4; k ++) {
                        DkR[i][j][k] = DkR[i][j][k] / (4*4*4);
                        DkI[i][j][k] = DkI[i][j][k] / (4*4*4);
                    }
                }
            }
            
            // ------------------------> Take the complex conjugate of Da <---------------------------
            for (int i = 0; i < 3; i ++) {
                for (int j = 0; j < 3; j ++) {
                    for (int k = 0; k < 3; k ++) {
                        DatI[i][j][k] = -DatI[i][j][k];
                    }
                }
            }
            
            // ------------------------> (Convolution) Multiply Da conjugate by Dk <-------------
            for (int i = 0; i < 3; i ++) {
                for (int j = 0; j < 3; j ++) {
                    for (int k = 0; k < 3; k ++) {
                        DatR[i][j][k] = DatR[i][j][k] * DkR[i][j][k];
                        DatI[i][j][k] = DatI[i][j][k] * DkI[i][j][k];
                    }
                }
            }
            //end of convolution
            
            
            
            //inverse transformation
            //First z-wise (slice)
            for (int j = 0; j < 4; j ++) {
                for (int k = 0; k < 4; k ++) {
                    float tmpSliR[4];
                    float tmpSliI[4];
                    
                    //throw present slice into a tmp array to do FFT upon
                    for (int i = 0; i < 4; i ++) {
                        tmpSliR[i] = DatR[i][j][k];
                        tmpSliI[i] = DatI[i][j][k];
                    }
                    
                    float4 tmpSliRFF;
                    tmpSliRFF.x = tmpSliR[0];
                    tmpSliRFF.y = tmpSliR[1];
                    tmpSliRFF.z = tmpSliR[2];
                    tmpSliRFF.w = tmpSliR[3];
                    
                    float4 tmpSliIFF;
                    tmpSliIFF.x = tmpSliI[0];
                    tmpSliIFF.y = tmpSliI[1];
                    tmpSliIFF.z = tmpSliI[2];
                    tmpSliIFF.w = tmpSliI[3];
                    
#ifdef FastFourierTransform
                    float8 Out = FFT(FFT_REVERSE, 2, tmpSliRFF, tmpSliIFF);
#else
                    float8 Out = DFT(FFT_REVERSE, 4, tmpSliRFF, tmpSliIFF);
#endif
                    
                    tmpSliR[0] = Out.s0;
                    tmpSliR[1] = Out.s1;
                    tmpSliR[2] = Out.s2;
                    tmpSliR[3] = Out.s3;
                    
                    tmpSliI[0] = Out.s4;
                    tmpSliI[1] = Out.s5;
                    tmpSliI[2] = Out.s6;
                    tmpSliI[3] = Out.s7;    
                    
                    //collect present slice into original 4*4*4 array
                    for (int i = 0; i < 4; i ++) {
                        DatR[i][j][k] = tmpSliR[i];
                        DatI[i][j][k] = tmpSliI[i];
                    }
                }
            }
            
            //Then y-wise (column wise inverse fft)
            for (int i = 0; i < 4; i ++) {
                for (int k = 0; k < 4; k ++) {
                    
                    float tmpColR[4];
                    float tmpColI[4];
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        tmpColR[j] = DatR[i][j][k];
                        tmpColI[j] = DatI[i][j][k];
                    }
                    
                    float4 tmpColRFF;
                    tmpColRFF.x = tmpColR[0];
                    tmpColRFF.y = tmpColR[1];
                    tmpColRFF.z = tmpColR[2];
                    tmpColRFF.w = tmpColR[3];
                    
                    float4 tmpColIFF;
                    tmpColIFF.x = tmpColI[0];
                    tmpColIFF.y = tmpColI[1];
                    tmpColIFF.z = tmpColI[2];
                    tmpColIFF.w = tmpColI[3];
                    
#ifdef FastFourierTransform
                    float8 Out = FFT(FFT_REVERSE, 2, tmpColRFF, tmpColIFF);
#else
                    float8 Out = DFT(FFT_REVERSE, 4, tmpColRFF, tmpColIFF);
#endif
                    
                    tmpColR[0] = Out.s0;
                    tmpColR[1] = Out.s1;
                    tmpColR[2] = Out.s2;
                    tmpColR[3] = Out.s3;
                    
                    tmpColI[0] = Out.s4;
                    tmpColI[1] = Out.s5;
                    tmpColI[2] = Out.s6;
                    tmpColI[3] = Out.s7;
                    
                    for (int j = 0; j < 4; j ++) {
                        // throw into a tmp array to do FFT upon
                        DatR[i][j][k] = tmpColR[j];
                        DatI[i][j][k] = tmpColI[j];
                    }
                }
            }
            
            //Finally x-wise (row wise inv fft)
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    float tmpRowR[4];
                    float tmpRowI[4];
                    
                    //collect a row
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        tmpRowR[k] = DatR[i][j][k];
                        tmpRowI[k] = DatI[i][j][k];
                    }
                    
                    float4 tmpRowRFF;
                    tmpRowRFF.x = tmpRowR[0];
                    tmpRowRFF.y = tmpRowR[1];
                    tmpRowRFF.z = tmpRowR[2];
                    tmpRowRFF.w = tmpRowR[3];
                    
                    float4 tmpRowIFF;
                    tmpRowIFF.x = tmpRowI[0];
                    tmpRowIFF.y = tmpRowI[1];
                    tmpRowIFF.z = tmpRowI[2];
                    tmpRowIFF.w = tmpRowI[3];
                    
                    
                    //apply FFT
#ifdef FastFourierTransform
                    float8 Out = FFT(FFT_REVERSE, 2, tmpRowRFF, tmpRowIFF);
#else
                    float8 Out = DFT(FFT_REVERSE, 4, tmpRowRFF, tmpRowIFF);
#endif
                    
                    tmpRowR[0] = Out.s0;
                    tmpRowR[1] = Out.s1;
                    tmpRowR[2] = Out.s2;
                    tmpRowR[3] = Out.s3;
                    
                    tmpRowI[0] = Out.s4;
                    tmpRowI[1] = Out.s5;
                    tmpRowI[2] = Out.s6;
                    tmpRowI[3] = Out.s7;
                    
                    // store the resulting row into original array
                    for (int k = 0; k < 4; k ++) {
                        // throw into a tmp array to do FFT upon
                        DatR[i][j][k] = tmpRowR[k];
                        DatI[i][j][k] = tmpRowI[k];
                    }
                }
            }
            
            // ------------------------> Multiply Da by (3*3*3) denoted Da' <------------------------ 
            for (int i = 0; i < 4; i ++) {
                for (int j = 0; j < 4; j ++) {
                    for (int k = 0; k < 4; k ++) {
                        DatR[i][j][k] = DatR[i][j][k] * (4*4*4);
                        DatI[i][j][k] = DatI[i][j][k] * (4*4*4);
                    }
                }
            }
            
            //populate back into a non dyadic matrix (3*3*3)
            for(int i = 0; i < 4; i++){
                for(int j = 0; j < 4; j++){
                    for(int k = 0; k < 4; k++){
                        if (k != 3 && j != 3 && i != 3) {
                            DaR[i][j][k] = DatR[i][j][k];
                            DaI[i][j][k] = DatI[i][j][k];
                        }
                    }
                }
            }
            
            if(c == 0){
                for (int i = 0; i < 3; i ++) {
                    for (int j = 0; j < 3; j ++) {
                        for (int k = 0; k < 3; k ++) {
                            WriteDaR[i][j][k].x = DaR[i][j][k];
                            WriteDaI[i][j][k].x = DaI[i][j][k];
                        }
                    }
                }
            }
            else if(c == 1){
                for (int i = 0; i < 3; i ++) {
                    for (int j = 0; j < 3; j ++) {
                        for (int k = 0; k < 3; k ++) {
                            WriteDaR[i][j][k].y = DaR[i][j][k];
                            WriteDaI[i][j][k].y = DaI[i][j][k];
                        }
                    }
                }
            }
            else{
                for (int i = 0; i < 3; i ++) {
                    for (int j = 0; j < 3; j ++) {
                        for (int k = 0; k < 3; k ++) {
                            WriteDaR[i][j][k].z = DaR[i][j][k];
                            WriteDaI[i][j][k].z = DaI[i][j][k];
                        }
                    }
                }
            }
            
            
        }
        
        
        //write this channel out
        for(int z = startImageCoord.z; z <= endImageCoord.z; z++){
            for(int y = startImageCoord.y; y <= endImageCoord.y; y++){
                for(int x= startImageCoord.x; x <= endImageCoord.x; x++){
#ifdef VolumetricRendering
#ifdef InternalStructureWithDICOMColouration
                    float i = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x;
                    float j = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y;
                    float k = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z;
                    float sF = 3;
                    //onion layering for rendering depicition
                    float tF = 1.0f;
                    if(i > 0.05f*tF && j > 0.05f*tF && k > 0.05f*tF){
                        if(i > 0.1f*tF && j > 0.1f*tF && k > 0.1f*tF){
                            if(i > 0.15f*tF && j > 0.15f*tF && k > 0.15f*tF){
                                if(i > 0.2f*tF && j > 0.2f*tF && k > 0.2f*tF){
                                    if(i > 0.25f*tF && j > 0.25f*tF && k > 0.25f*tF){
                                        if(i > 0.3f*tF && j > 0.3f*tF && k > 0.3f*tF){
                                            if(i > 0.35f*tF && j > 0.35f*tF && k > 0.35f*tF){
                                                if(i > 0.4f*tF && j > 0.4f*tF && k > 0.4f*tF){
                                                    if(i > 0.45f*tF && j > 0.45f*tF && k > 0.45f*tF){
                                                        if(i > 0.5f*tF && j > 0.5f*tF && k > 0.5f*tF){
                                                            write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k,1.0f));
                                                        }
                                                    }else{
                                                        write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k,1.0f));
                                                    }
                                                }else{
                                                    write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k,0.8f));
                                                }
                                            }else{
                                                write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k,0.8f));
                                            }
                                        }else{
                                            write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF/2,j*sF,k,0.7));
                                        }
                                    }else{
                                        write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF*sF/2,j*sF,k,0.5));
                                    }
                                }else{
                                    write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i,j,k*sF,0.2f));
                                }
                            }else{
                                write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i,j,k*sF,0.2f));
                            }
                        }
                        else{
                            write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i,j,k*sF,0.2f)); 
                        }
                    }else{
                        write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i,j,k*sF,0.05f));
                    }
#endif            
        #ifdef InternalStructure
                    float i = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x;
                    float j = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y;
                    float k = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z;
                    float sF = 2;
                    //onion layering for rendering depicition
                    float tF = 1.0f;
                    if(i > 0.05f*tF && j > 0.05f*tF && k > 0.05f*tF){
                        if(i > 0.1f*tF && j > 0.1f*tF && k > 0.1f*tF){
                            if(i > 0.15f*tF && j > 0.15f*tF && k > 0.15f*tF){
                                if(i > 0.2f*tF && j > 0.2f*tF && k > 0.2f*tF){
                                    if(i > 0.25f*tF && j > 0.25f*tF && k > 0.25f*tF){
                                        if(i > 0.3f*tF && j > 0.3f*tF && k > 0.3f*tF){
                                            if(i > 0.35f*tF && j > 0.35f*tF && k > 0.35f*tF){
                                                if(i > 0.4f*tF && j > 0.4f*tF && k > 0.4f*tF){
                                                    if(i > 0.45f*tF && j > 0.45f*tF && k > 0.45f*tF){
                                                        if(i > 0.5f*tF && j > 0.5f*tF && k > 0.5f*tF){
                                                                write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,1));
                                                            }
                                                        }else{
                                                            write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,0.9));
                                                        }
                                                    }else{
                                                        write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,0.8));
                                                    }
                                                }else{
                                                    write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,0.7));
                                                }
                                            }else{
                                                write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,0.6));
                                            }
                                        }else{
                                            write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,0.5));
                                        }
                                    }else{
                                        write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,0.4f));
                                    }
                                }else{
                                    write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,0.3f));
                                }
                            }
                            else{
                            write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,0.2f)); 
                            }
                        }else{
                            write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,0.05f));
                        }
        #endif
        #ifdef MarchingCubes
                    float i = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x;
                    float j = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y;
                    float k = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z;
                    float sF = 1;
                    
                    if(i > 0.05f && j > 0.05f && k > 0.05f){
                        write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,1.0f));
                    } 
        #endif
        #ifdef RegularPlanar
                    float i = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x;
                    float j = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y;
                    float k = WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z;
                    float sF = 1;

                    if(i > 0.05f && j > 0.05f && k > 0.05f){
                        write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,1.0f));
                    }else{
                        write_imagef(dstImg, (int4)(x,y,z,1),(float4)(i*sF,j*sF,k*sF,0.1f));
                    }
        #endif
                    
#else
                    //output over these output coordinates
                    write_imagef(dstImg, (int4)(x,y,z,1),(float4)(WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].x,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].y,WriteDaR[z - startImageCoord.z][y - startImageCoord.y][x - startImageCoord.x].z,1)); 
#endif
                }
            }
        }
    }
}
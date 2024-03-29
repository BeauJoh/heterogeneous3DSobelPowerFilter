/*
 *  main.cpp
 *  heterogeneous3DSobelPowerFilter
 *
 *
 *  Created by Beau Johnston on 17/06/11.
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

#include "global.h"
#include "openCLUtilities.h"
#include "openGLVisualiser.h"

#include <getopt.h>
#include <string>
#include <iostream>
#include <time.h>

using namespace std;

// getopt argument parser variables
string imageFileName;
string kernelFileName;
string outputImageFileName;

// OpenCL variables
int err, gpu;                       // error code returned from api calls
size_t *globalWorksize;             // global domain size for our calculation
size_t *localWorksize;              // local domain size for our calculation
cl_device_id device_id;             // compute device id 
cl_context context;                 // compute context
cl_command_queue commands;          // compute command queue
cl_program program;                 // compute program
cl_kernel kernel;                   // compute kernel
cl_sampler sampler;
cl_mem input;                       // device memory used for the input array
cl_mem output;                      // device memory used for the output array
int width;
int height;                         //input and output image specs
int depth;


static inline int parseCommandLine(int argc , char** argv){
    {
        int c;
        while (true)
        {
            static struct option long_options[] =
            {
                /* These options don't set a flag.
                 We distinguish them by their indices. */
                {"kernel",required_argument,       0, 'k'},
                {"image",  required_argument,       0, 'i'},
                {"output-image", required_argument, 0, 'o'},
                {0, 0, 0, 0}
            };
            /* getopt_long stores the option index here. */
            int option_index = 0;
            
            c = getopt_long (argc, argv, ":k:i:o:",
                             long_options, &option_index);
            
            /* Detect the end of the options. */
            if (c == -1)
                break;
            
            switch (c)
            {
                case 0:
                    /* If this option set a flag, do nothing else now. */
                    if (long_options[option_index].flag != 0)
                        break;
                    printf ("option %s", long_options[option_index].name);
                    if (optarg)
                        printf (" with arg %s", optarg);
                    printf ("\n");
                    break;
                    
                case 'i':
                    imageFileName = optarg ;
                    break;
                    
                case 'o':
                    outputImageFileName = optarg;
                    break;
                    
                case 'k':
                    kernelFileName = optarg ;
                    break;
                    
                    
                case '?':
                    /* getopt_long already printed an error message. */
                    break;
                    
                default:
                    ;
                    
            }
        }
        
        
        /* Print any remaining command line arguments (not options). */
        if (optind < argc)
        {
            while (optind < argc)
            /*
             printf ("%s ", argv[optind]);
             putchar ('\n');
             */
                optind++;
        }
    }
    return 1;
};

OpenCLUtilities* openCLUtilities;

void createClassObjects(void){
    openCLUtilities = new OpenCLUtilities();
}

void destroyClassObjects(void){
    delete openCLUtilities;
}

void cleanKill(int errNumber){
    clReleaseMemObject(input);
	clReleaseMemObject(output);
	clReleaseProgram(program);
    clReleaseSampler(sampler);
	clReleaseKernel(kernel);
	clReleaseCommandQueue(commands);
	clReleaseContext(context);
    
    destroyClassObjects();
    exit(errNumber);
}

typedef struct {
    float real;
    float imag; 
} Complex;

int main(int argc, char *argv[])
{	
    parseCommandLine(argc , argv);
    
    createClassObjects();
    
	// Connect to a compute device
	//
#ifdef USING_GPU
	gpu = 1;
#else
    gpu = 0;
#endif
	
    cl_uint num_devices;
    
    if(clGetDeviceIDs(NULL, gpu ? CL_DEVICE_TYPE_GPU : CL_DEVICE_TYPE_CPU, 1, &device_id, &num_devices) != CL_SUCCESS)  {
		cout << "Failed to create a device group!" << endl;
        cleanKill(EXIT_FAILURE);
    }
    
	// Create a compute context 
	//
	if(!(context = clCreateContext(0, 1, &device_id, NULL, NULL, &err))){
		cout << "Failed to create a compute context!" << endl;
        cleanKill(EXIT_FAILURE);
    }
    
    //use only one core applying device fission (not supported on intel i7 early MBP)
//#ifdef DEBUG
//    printf("number of devices %i\n", num_devices);
//    char buffer[2048];
//    size_t len;
//    
//    clGetDeviceInfo(device_id,
//                           CL_DEVICE_EXTENSIONS,
//                           sizeof(buffer),
//                           buffer,
//                           &len);
//    
//    printf("device id has values : \n %s \n\n\n", buffer);
//    
//    cl_device_partition_property_ext props[] = {
//        CL_DEVICE_PARTITION_EQUALLY_EXT, 1,
//        CL_PROPERTIES_LIST_END_EXT,
//        0
//    };
//    
//#endif
    
//    if (devices.getInfo<CL_DEVICE_EXTENSIONS>(). find(
//                                                      "cl_ext_device_fission") == std::string::npos) {
//        exit(-1); }
    
    
	// Create a command commands
	//
	if(!(commands = clCreateCommandQueue(context, device_id, 0, &err))) {
		cout << "Failed to create a command commands!" << endl;
        cleanKill(EXIT_FAILURE);
    }
    
    // Load kernel source code
    //
    //	char *source = load_program_source((char*)"sobel_opt1.cl");
    char *source = openCLUtilities->load_program_source((char*)kernelFileName.c_str());
    if(!source)
    {
        cout << "Error: Failed to load compute program from file!" << endl;
        cleanKill(EXIT_FAILURE);
    }
    
	// Create the compute program from the source buffer
	//
	if(!(program = clCreateProgramWithSource(context, 1, (const char **) &source, NULL, &err))){
		cout << "Failed to create compute program!" << endl;
        cleanKill(EXIT_FAILURE);
    }
    
	// Build the program executable
	//
	err = clBuildProgram(program, 0, NULL, NULL, NULL, NULL);
	if (err != CL_SUCCESS)
	{
		size_t len;
		char buffer[2048];
		cout << "Error: Failed to build program executable!" << endl;
		clGetProgramBuildInfo(program, device_id, CL_PROGRAM_BUILD_LOG, sizeof(buffer), buffer, &len);
		cout << buffer << endl;
        cleanKill(EXIT_FAILURE);
	}
    
    if(!openCLUtilities->doesGPUSupportImageObjects(device_id)){
        cleanKill(EXIT_FAILURE);
    }
	
	// Create the compute kernel in the program we wish to run
	//
#ifdef USING_GPU
	kernel = clCreateKernel(program, "sobel3D", &err);
#else
    //kernel = clCreateKernel(program, "sobel3DCPU", &err);
    //kernel = clCreateKernel(program, "sobel3D", &err);
    kernel = clCreateKernel(program, "sobel3DwInternalStructureEmphasis", &err);
#endif
    
	if (!kernel || err != CL_SUCCESS){
		cout << "Failed to create compute kernel!" << endl;
        cleanKill(EXIT_FAILURE);
    }
    
    // Get GPU image support, useful for debugging
    // getGPUUnitSupportedImageFormats(context);
    
    
    //  specify the image format that the images are represented as... 
    //  by default to support OpenCL they must support 
    //  format.image_channel_data_type = CL_UNORM_INT8;
    //  i.e. Each channel component is a normalized unsigned 8-bit integer value.
    //
    //	format.image_channel_order = CL_RGBA;
    //
    //  format is collected with the LoadImage function
    cl_image_format format; 
    
    //  create input image buffer object to read results from
    input = openCLUtilities->LoadStackOfImages(context, (char*)imageFileName.c_str(), width, height, depth, format);
    
    //  create output buffer object, to store results
    output = clCreateImage3D(context, 
                             CL_MEM_WRITE_ONLY, 
                             &format, 
                             width, 
                             height,
                             depth,
                             openCLUtilities->getImageRowPitch(), 
                             openCLUtilities->getImageSlicePitch(),
                             NULL, 
                             &err);
    
    if(openCLUtilities->there_was_an_error(err)){
        cout << "Output Image Buffer creation error!" << endl;
        cleanKill(EXIT_FAILURE);
    }    
    
    
    //  if either input of output are empty, crash and burn
	if (!input || !output ){
		cout << "Failed to allocate device memory!" << endl;
        cleanKill(EXIT_FAILURE);
	}
    
    
    // Create sampler for sampling image object 
    sampler = clCreateSampler(context,
                              CL_FALSE, // Non-normalized coordinates 
                              CL_ADDRESS_CLAMP_TO_EDGE, 
                              CL_FILTER_NEAREST, 
                              &err);
    
    if(openCLUtilities->there_was_an_error(err)){
        cout << "Error creating CL sampler object." << endl;
        cleanKill(EXIT_FAILURE);
    }
    
    
	// Set the arguments to our compute kernel
	//
	err  = clSetKernelArg(kernel, 0, sizeof(cl_mem), &input);
	err |= clSetKernelArg(kernel, 1, sizeof(cl_mem), &output);
    err |= clSetKernelArg(kernel, 2, sizeof(cl_sampler), &sampler); 
    err |= clSetKernelArg(kernel, 3, sizeof(cl_int), &width);
    err |= clSetKernelArg(kernel, 4, sizeof(cl_int), &height);
    err |= clSetKernelArg(kernel, 5, sizeof(cl_int), &depth);
    //depth arg here!
    
    if(openCLUtilities->there_was_an_error(err)){
        cout << "Error: Failed to set kernel arguments! " << err << endl;
        cleanKill(EXIT_FAILURE);
    }    
    
    

    //cout << "max kernel size is : " << CL_KERNEL_WORK_GROUP_SIZE << endl;
    //size_t localWorksize[3] = {0, 0, 0};
    size_t localWorksize[3] = {3, 3, 3};
    
    //cout << "Image Width " << getImageWidth() << endl;
    //cout << "Scaled Image Width " << RoundUp((int)localWorksize[0], getImageWidth()) << endl;
    
    size_t globalWorksize[3] =  {width, height, depth};
    
    //  Start up the kernels in the GPUs
    //
    
    timeval startTime, stopTime;

    gettimeofday(&startTime, NULL);
    
	err = clEnqueueNDRangeKernel(commands, kernel, 3, localWorksize, globalWorksize, NULL, NULL, NULL, NULL);
    
	if (openCLUtilities->there_was_an_error(err))
	{
        cout << openCLUtilities->print_cl_errstring(err) << endl;
		cout << "Failed to execute kernel!, " << err << endl;
        cleanKill(EXIT_FAILURE);
	}
	
	// Wait for the command commands to get serviced before reading back results
	//
	clFinish(commands);
    
    // stop timer and show times
    gettimeofday(&stopTime, NULL);
    double elapsedTime;
    
    elapsedTime = (stopTime.tv_sec - startTime.tv_sec)*1000.0;
    elapsedTime += (stopTime.tv_usec - startTime.tv_usec) /1000.0;
    printf("%f  ms.\n", elapsedTime);
    
    
	// Read back the results from the device to verify the output
	//
    uint8* bigBuffer = new uint8[openCLUtilities->getImageSize()*depth];        
    
    size_t origin[3] = { 0, 0, 0 };
    size_t region[3] = { width, height, depth};
    
    cl_command_queue queue = clCreateCommandQueue(
                                                  context, 
                                                  device_id, 
                                                  0, 
                                                  &err);
    
    // Read image to buffer with implicit row pitch calculation
    //
    err = clEnqueueReadImage(queue, output,
                             CL_TRUE, origin, region, openCLUtilities->getImageRowPitch(), openCLUtilities->getImageSlicePitch(), bigBuffer, 0, NULL, NULL);
    
    
    //printImage(buffer, getImageSize()*depth);
    
    //load all images into a buffer
    for (int i = 0; i < depth; i++) {
        uint8 *buffer = new uint8[openCLUtilities->getImageSize()];
        memcpy(buffer, bigBuffer+(i*openCLUtilities->getImageSize()), openCLUtilities->getImageSize());
        
        string file = outputImageFileName.substr(outputImageFileName.find_last_of('/')+1);
        string path = outputImageFileName.substr(0, outputImageFileName.find_last_of('/')+1);
        
        string cutDownFile = file.substr(0, file.find_last_of('.'));
        string extension = file.substr(file.find_last_of('.'));
        
        
        string newName = cutDownFile;
        char numericalRepresentation[200];
        sprintf(numericalRepresentation, "%d", i);
        newName.append(numericalRepresentation);
        newName.append(extension);
        
        newName = path.append(newName);
        
        openCLUtilities->SaveImage((char*)newName.c_str(), buffer, width, height);   
        
    } 
    #ifdef VolumetricRendering
    plotMain(argc, argv, bigBuffer, width, height, depth);
    #endif
    // Shutdown and cleanup
	//
	cleanKill(EXIT_SUCCESS);
	//return 1;
}
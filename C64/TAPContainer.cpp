/*
 * (C) 2015 - 2017 Dirk W. Hoffmann. All rights reserved.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include "TAPContainer.h"

TAPContainer::TAPContainer()
{
    setDescription("TAPContainer");
    data = NULL;
    dealloc();
}

TAPContainer::~TAPContainer()
{
    dealloc();
}

bool
TAPContainer::isTAPFile(const char *filename)
{
    int magic_bytes[] = {0x43, 0x36, 0x34, 0x2D, 0x54, 0x41, 0x50, 0x45, 0x2D, 0x52, 0x41, 0x57, EOF};
    
    assert (filename != NULL);
    
    if (!checkFileSuffix(filename, ".TAP") && !checkFileSuffix(filename, ".tap"))
        return false;

    if (!checkFileSize(filename, 0x15, -1))
        return false;
    
    if (!checkFileHeader(filename, magic_bytes))
        return false;
    
    return true;
}

TAPContainer *
TAPContainer::containerFromTAPFile(const char *filename)
{
    TAPContainer *container = new TAPContainer();
    
    if (!container->readFromFile(filename)) {
        delete container;
        return NULL; 
    }

    container->debug(1, "TAP container created from file %s.\n", filename);
    return container;
}

void
TAPContainer::dealloc()
{
    if (data) free(data);
    data = NULL;
    size = 0;
    fp = -1;
}

const char *
TAPContainer::getName()
{
    unsigned i;
    
    for (i = 0; i < 17; i++) {
        name[i] = data[0x08+i];
    }
    name[i] = 0x00;
    return name;
}

bool
TAPContainer::fileIsValid(const char *filename)
{
    return isTAPFile(filename);
}

bool
TAPContainer::readFromBuffer(const uint8_t *buffer, unsigned length)
{
    if ((data = (uint8_t *)malloc(length)) == NULL)
        return false;
    
    memcpy(data, buffer, length);
    size = length;
    
    int l = LO_LO_HI_HI(data[0x10], data[0x11], data[0x12], data[0x13]);
    if (l + 0x14 /* Header */ != size) {
        warn("Size mismatch! Archive should have %d data bytes, found %d\n", l, size - 0x14);
    }
        
    return true;
}

unsigned
TAPContainer::writeToBuffer(uint8_t *buffer)
{
    assert(data != NULL);
    
    if (buffer) {
        memcpy(buffer, data, size);
    }
    return size;
}

#if 0
void
TAPContainer::selectItem(int n)
{
    if (n == 0)
        fp = 0x0014; // Rewind
    else
        fp = -1;     // No such item
}

int
TAPContainer::getByte()
{
    int result;
    
    if (fp < 0)
        return -1;
    
    // get byte
    result = data[fp];
    
    // check for end of file
    if (fp == (size - 1)) {
        fp = -1;
    } else {
        // advance file pointer
        fp++;
    }
    
    return result;
}

#endif

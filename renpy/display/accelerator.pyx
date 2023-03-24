#cython: profile=False
# Copyright 2004-2023 Tom Rothamel <pytom@bishoujo.us>
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

from __future__ import print_function

import renpy
import math
from renpy.display.matrix cimport Matrix
from renpy.display.render cimport Render, Matrix2D, render
from renpy.display.core import absolute

from sdl2 cimport *
from pygame_sdl2 cimport *

import_pygame_sdl2()

################################################################################
# Surface copying
################################################################################


def nogil_copy(src, dest):
    """
    Does a gil-less blit of src to dest, with minimal locking.
    """

    cdef SDL_Surface *src_surf
    cdef SDL_Surface *dst_surf

    src_surf = PySurface_AsSurface(src)
    dest_surf = PySurface_AsSurface(dest)

    with nogil:
        SDL_SetSurfaceBlendMode(src_surf, SDL_BLENDMODE_NONE)
        SDL_UpperBlit(src_surf, NULL, dest_surf, NULL)

################################################################################
# Interpolate Orientation
################################################################################


def quaternion_slerp(complete, old, new):
    """
    Interpolate orientation angle.
    """

    if old == new:
        return new

    #select the shorten root
    old_x, old_y, old_z = old
    old_x = old_x % 360
    old_y = old_y % 360
    old_z = old_z % 360
    new_x, new_y, new_z = new
    new_x = new_x % 360
    new_y = new_y % 360
    new_z = new_z % 360
    if new_x - old_x > 180:
        new_x = new_x - 360
    if new_y - old_y > 180:
        new_y = new_y - 360
    if new_z - old_z > 180:
        new_z = new_z - 360


    #z-y-x Euler angles to quaternion conversion
    #https://en.wikipedia.org/wiki/Conversion_between_quaternions_and_Euler_angles
    old_x_div_2 = math.radians(old_x) * 0.5
    old_y_div_2 = math.radians(old_y) * 0.5
    old_z_div_2 = math.radians(old_z) * 0.5
    cx = math.cos(old_x_div_2)
    sx = math.sin(old_x_div_2)
    cy = math.cos(old_y_div_2)
    sy = math.sin(old_y_div_2)
    cz = math.cos(old_z_div_2)
    sz = math.sin(old_z_div_2)

    old_q_x = sx * cy * cz - cx * sy * sz
    old_q_y = cx * sy * cz + sx * cy * sz
    old_q_z = cx * cy * sz - sx * sy * cz
    old_q_w = cx * cy * cz + sx * sy * sz

    new_x_div_2 = math.radians(new_x) * 0.5
    new_y_div_2 = math.radians(new_y) * 0.5
    new_z_div_2 = math.radians(new_z) * 0.5
    cx = math.cos(new_x_div_2)
    sx = math.sin(new_x_div_2)
    cy = math.cos(new_y_div_2)
    sy = math.sin(new_y_div_2)
    cz = math.cos(new_z_div_2)
    sz = math.sin(new_z_div_2)

    new_q_x = sx * cy * cz - cx * sy * sz
    new_q_y = cx * sy * cz + sx * cy * sz
    new_q_z = cx * cy * sz - sx * sy * cz
    new_q_w = cx * cy * cz + sx * sy * sz


    #calculate new quaternion between old and new.
    old_q_mul_new_q = (old_q_x * new_q_x + old_q_y * new_q_y + old_q_z * new_q_z + old_q_w * new_q_w)
    dot = old_q_mul_new_q
    if dot > 1.0:
        dot = 1.0
    elif dot < -1.0:
        dot = -1.0
    theta = abs(math.acos(dot))

    st = math.sin(theta)

    sut = math.sin(theta * complete)
    sout = math.sin(theta * (1 - complete))

    coeff1 = sout / st
    coeff2 = sut / st

    q_x = coeff1 * old_q_x + coeff2 * new_q_x
    q_y = coeff1 * old_q_y + coeff2 * new_q_y
    q_z = coeff1 * old_q_z + coeff2 * new_q_z
    q_w = coeff1 * old_q_w + coeff2 * new_q_w


    #Quaternion to z-y-x Euler angles conversion
    #https://en.wikipedia.org/wiki/Conversion_between_quaternions_and_Euler_angles
    sinx_cosp = 2 * (q_w * q_x + q_y * q_z)
    cosx_cosp = 1 - 2 * (q_x * q_x + q_y * q_y)
    siny = 2 * (q_w * q_y - q_z * q_x)
    sinz_cosp1 = 2 * (q_x * q_y - q_w * q_z)
    cosz_cosp1 = 1 - 2 * (q_x * q_x + q_z * q_z)
    sinz_cosp2 = 2 * (q_w * q_z + q_x * q_y)
    cosz_cosp2 = 1 - 2 * (q_y * q_y + q_z * q_z)

    if siny >= 1:
        x = 0
        y = math.pi/2
        z = math.atan2(sinz_cosp1, cosz_cosp1)
    elif siny <= -1:
        x = 0
        y = -math.pi/2
        z = math.atan2(sinz_cosp1, cosz_cosp1)
    else:
        x = math.atan2(sinx_cosp, cosx_cosp)
        if siny > 1.0:
            siny = 1.0
        elif siny < -1.0:
            siny = -1.0
        y = math.asin(siny)
        z = math.atan2(sinz_cosp2, cosz_cosp2)
    x = math.degrees(x) % 360
    y = math.degrees(y) % 360
    z = math.degrees(z) % 360

    return (x, y, z)


def get_poi(state):
    """
    For the given state, return the poi - the point that point_to looks at.
    """

    point_to = state.point_to

    if isinstance(point_to, tuple) and len(point_to) == 3:
        return point_to

    if isinstance(point_to, renpy.display.transform.Camera):

        if state.perspective:
            raise Exception("The point_to transform property for camera should not be True.")

        layer = point_to.layer
        sle = renpy.game.context().scene_lists

        d = sle.camera_transform.get(layer, None)

        if not isinstance(d, renpy.display.motion.Transform):
            return None

        perspective = d.perspective

        if perspective is True:
            perspective = renpy.config.perspective

        elif isinstance(perspective, (int, float)):
            perspective = (renpy.config.perspective[0], perspective, renpy.config.perspective[2])

        if not perspective:
            return None

        z11 = perspective[1]
        width = renpy.config.screen_width
        height = renpy.config.screen_height

        placement = (d.xpos, d.ypos, d.xanchor, d.yanchor, d.xoffset, d.yoffset, True)
        xplacement, yplacement = renpy.display.core.place(width, height, width, height, placement)

        return (xplacement + width / 2, yplacement + height / 2, d.zpos + z11)

    raise Exception("The point_to transform property should be None, a 3-tuple (x, y, z), or True.")


################################################################################
# Transform render function
################################################################################

cdef Matrix2D IDENTITY
IDENTITY = renpy.display.render.IDENTITY


# The distance to the 1:1 plan, in the current perspective.
z11 = 0.0

# This file contains implementations of methods of classes that
# are found in other files, for performance reasons.

def make_mesh(cr, state):
    """
    Makes a mesh out a render.

    `cr`
        The render to convert to a mesh.

    `blur`
        If not None, the amount of blur to apply to the mesh.
    """

    mr = Render(cr.width, cr.height)

    mesh = state.mesh
    blur = state.blur
    mesh_pad = state.mesh_pad

    if state.mesh_pad:

        if len(mesh_pad) == 4:
            pad_left, pad_top, pad_right, pad_bottom = mesh_pad
        else:
            pad_right, pad_bottom = mesh_pad
            pad_left = 0
            pad_top = 0

        padded = Render(cr.width + pad_left + pad_right, cr.height + pad_top + pad_bottom)
        padded.blit(cr, (pad_left, pad_top))

        cr = padded

    mr.blit(cr, (0, 0))

    mr.operation = renpy.display.render.FLATTEN
    mr.add_shader("renpy.texture")

    if isinstance(mesh, tuple):
        mesh_width, mesh_height = mesh

        mr.mesh = renpy.gl2.gl2mesh2.Mesh2.texture_grid_mesh(
            mesh_width, mesh_height,
            0.0, 0.0, cr.width, cr.height,
            0.0, 0.0, 1.0, 1.0)
    else:
        mr.mesh = True

    if blur is not None:
        mr.add_shader("-renpy.texture")
        mr.add_shader("renpy.blur")
        mr.add_uniform("u_renpy_blur_log2", math.log(blur, 2))

    return mr

def tile_and_pan(cr, state):

    cwidth = cr.width
    cheight = cr.height

    # Tile the child to make it bigger.

    xtile = state.xtile
    ytile = state.ytile

    xpan = state.xpan
    ypan = state.ypan

    # Tiling.
    if (xtile != 1) or (ytile != 1):
        tcr = renpy.display.render.Render(cwidth * xtile, cheight * ytile)

        for i in range(xtile):
            for j in range(ytile):
                tcr.blit(cr, (i * cwidth, j * cheight))

        cr = tcr

    # Panning.
    if (xpan is not None) or (ypan is not None):

        if xpan is not None:
            xpan = (xpan % 360) / 360.0
            pan_x = cwidth * xpan
            pan_w = cwidth
        else:
            pan_x = 0
            pan_w = cr.width

        if ypan is not None:
            ypan = (ypan % 360) / 360.0
            pan_y = cheight * ypan
            pan_h = cheight
        else:
            pan_y = 0
            pan_h = cr.height

        tcr = renpy.display.render.Render(pan_w, pan_h)

        for xpano in [ 0, cwidth ] if (xpan is not None) else [ 0 ]:
            for ypano in [ 0, cheight ] if (ypan is not None) else [ 0 ]:
                tcr.subpixel_blit(cr, (xpano - pan_x, ypano - pan_y))

        tcr.xclipping = True
        tcr.yclipping = True

        cr = tcr

    return cr

def cropping(cr, state, width, height):

    xo = 0
    yo = 0
    clipping = False

    crop = state.crop

    crop_relative = state.crop_relative

    if crop_relative is None:
        crop_relative = renpy.config.crop_relative_default

    def relative(n, base, limit):
        if isinstance(n, (int, absolute)):
            return n
        else:
            return min(int(n * base), limit)

    if crop is not None:

        if crop_relative:
            x, y, w, h = crop

            x = relative(x, width, width)
            y = relative(y, height, height)
            w = relative(w, width, width - x)
            h = relative(h, height, height - y)

            crop = (x, y, w, h)

    if (state.corner1 is not None) and (crop is None) and (state.corner2 is not None):
        x1, y1 = state.corner1
        x2, y2 = state.corner2

        if crop_relative:
            x1 = relative(x1, width, width)
            y1 = relative(y1, height, height)
            x2 = relative(x2, width, width)
            y2 = relative(y2, height, height)

        if x1 > x2:
            x3 = x1
            x1 = x2
            x2 = x3

        if y1 > y2:
            y3 = y1
            y1 = y2
            y2 = y3

        crop = (x1, y1, x2-x1, y2-y1)

    if crop is not None:

        negative_xo, negative_yo, width, height = crop

        if state.rotate is not None:
            clipcr = Render(width, height)
            clipcr.subpixel_blit(cr, (-negative_xo, -negative_yo))
            clipcr.xclipping = True
            clipcr.yclipping = True
            cr = clipcr
        else:
            xo = -negative_xo
            yo = -negative_yo
            clipping = True

    return (cr, xo, yo, clipping)


def transform_render(self, widtho, heighto, st, at):

    cdef double rxdx, rxdy, rydx, rydy
    cdef double cosa, sina
    cdef double xo, px
    cdef double yo, py
    cdef float zoom, xzoom, yzoom
    cdef double cw, ch, nw, nh
    cdef Render rv, cr, tcr
    cdef double angle
    cdef double alpha
    cdef double width = widtho
    cdef double height = heighto
    cdef double cwidth
    cdef double cheight
    cdef int xtile, ytile
    cdef int i, j

    global z11

    # Prevent time from ticking backwards, as can happen if we replace a
    # transform but keep its state.
    if st + self.st_offset <= self.st:
        self.st_offset = self.st - st
    if at + self.at_offset <= self.at:
        self.at_offset = self.at - at

    self.st = st = st + self.st_offset
    self.at = at = at + self.at_offset

    # Update the state.
    self.update_state()

    # Render the child.
    child = self.child

    if child is None:
        child = renpy.display.transform.get_null()

    state = self.state

    xsize = state.xsize
    ysize = state.ysize
    fit = state.fit

    if xsize is not None:
        if (type(xsize) is float) and renpy.config.relative_transform_size:
            xsize *= widtho
        widtho = xsize
    if ysize is not None:
        if (type(ysize) is float) and renpy.config.relative_transform_size:
            ysize *= heighto
        heighto = ysize

    # Figure out the perspective.
    perspective = state.perspective

    if perspective is True:
        perspective = renpy.config.perspective
    elif perspective is False:
        perspective = None
    elif isinstance(perspective, (int, float)):
        perspective = (renpy.config.perspective[0], perspective, renpy.config.perspective[2])

    # Set the z11 distance (might seem useless, is not).
    old_z11 = z11

    if perspective:
        z11 = perspective[1]

    cr = render(child, widtho, heighto, st - self.child_st_base, at)

    # Reset the z11 distance.
    z11 = old_z11

    cr = tile_and_pan(cr, state)

    mesh = state.mesh or (True if state.blur else None)

    if mesh and not perspective:
        mr = cr = make_mesh(cr, state)

    # The width and height of the child.
    width = cr.width
    height = cr.height

    self.child_size = width, height

    # The reverse matrix.
    rxdx = 1
    rxdy = 0
    rydx = 0
    rydy = 1

    xo = 0
    yo = 0

    # Cropping.
    cr, xo, yo, clipping = cropping(cr, state, width, height)


    # Size.
    if (width != 0) and (height != 0):
        maxsize = state.maxsize
        mul = None

        if (maxsize is not None):
            maxsizex, maxsizey = maxsize
            mul = min(maxsizex / width, maxsizey / height)

        scale = []
        if xsize is not None:
            scale.append(xsize / width)
        if ysize is not None:
            scale.append(ysize / height)

        if fit and not scale:
            scale = [widtho / width, heighto / height]

        if fit is None:
            fit = 'fill'

        if scale:
            if fit == 'scale-up':
                mul = max(1, *scale)
            elif fit == 'scale-down':
                mul = min(1, *scale)
            elif fit == 'contain':
                mul = min(scale)
            elif fit == 'cover':
                mul = max(scale)
            else:
                if xsize is None:
                    xsize = width
                if ysize is None:
                    ysize = height

        if mul is not None:
            xsize = mul * width
            ysize = mul * height

        if (xsize is not None) and (ysize is not None) and ((xsize, ysize) != (width, height)):
            nw = xsize
            nh = ysize

            xzoom = 1.0 * nw / width
            yzoom = 1.0 * nh / height

            rxdx = xzoom
            rydy = yzoom

            xo *= xzoom
            yo *= yzoom

            width = xsize
            height = ysize

    # zoom
    zoom = state.zoom
    xzoom = zoom * <double> state.xzoom
    yzoom = zoom * <double> state.yzoom

    if xzoom != 1:

        rxdx *= xzoom

        if xzoom < 0:
            width *= -xzoom
        else:
            width *= xzoom

        xo *= xzoom
        # origin corrections for flipping
        if xzoom < 0:
            xo += width

    if yzoom != 1:

        rydy *= yzoom

        if yzoom < 0:
            height *= -yzoom
        else:
            height *= yzoom

        yo *= yzoom
        # origin corrections for flipping
        if yzoom < 0:
            yo += height


    # Rotation.
    rotate = state.rotate
    if (rotate is not None) and (not perspective):

        cw = width
        ch = height

        angle = rotate * 3.1415926535897931 / 180

        cosa = math.cos(angle)
        sina = math.sin(angle)

        # reverse = Matrix2D(xdx, xdy, ydx, ydy) * reverse

        # We know that at this point, rxdy and rydx are both 0, so
        # we can simplify these formulae a bit.
        rxdy = rydy * -sina
        rydx = rxdx * sina
        rxdx *= cosa
        rydy *= cosa

        # first corner point (changes with flipping)
        px = cw / 2.0
        if xzoom < 0:
            px = -px
        py = ch / 2.0
        if yzoom < 0:
            py = -py

        if state.rotate_pad:
            width = height = math.hypot(cw, ch)

            xo = -px * cosa + py * sina
            yo = -px * sina - py * cosa

        else:
            xo = -px * cosa + py * sina
            yo = -px * sina - py * cosa

            x2 = -px * cosa - py * sina
            y2 = -px * sina + py * cosa

            x3 =  px * cosa - py * sina
            y3 =  px * sina + py * cosa

            x4 =  px * cosa + py * sina
            y4 =  px * sina - py * cosa

            width = max(xo, x2, x3, x4) - min(xo, x2, x3, x4)
            height = max(yo, y2, y3, y4) - min(yo, y2, y3, y4)

        xo += width / 2.0
        yo += height / 2.0

    rv = Render(width, height)

    if state.matrixcolor:
        matrix = state.matrixcolor

        if callable(matrix):
            matrix = matrix(None, 1.0)

        if not isinstance(matrix, renpy.display.matrix.Matrix):
            raise Exception("matrixcolor requires a Matrix (not im.matrix, got %r)" % (matrix,))

        rv.add_shader("renpy.matrixcolor")
        rv.add_uniform("u_renpy_matrixcolor", matrix)

    # Default case - no transformation matrix.
    if rxdx == 1 and rxdy == 0 and rydx == 0 and rydy == 1:
        self.reverse = IDENTITY
    else:
        self.reverse = Matrix2D(rxdx, rxdy, rydx, rydy)

    if state.point_to is not None:
        poi = get_poi(state)
    else:
        poi = None

    orientation = state.orientation
    if orientation:
        xorientation, yorientation, zorientation = orientation

    xyz_rotate = False
    if state.xrotate or state.yrotate or state.zrotate:
        xyz_rotate = True
        xrotate = state.xrotate or 0
        yrotate = state.yrotate or 0
        zrotate = state.zrotate or 0

    # xpos and ypos.
    if perspective:
        placement = (state.xpos, state.ypos, state.xanchor, state.yanchor, state.xoffset, state.yoffset, True)
        xplacement, yplacement = renpy.display.core.place(width, height, width, height, placement)

        self.reverse = Matrix.offset(-xplacement, -yplacement, -state.zpos) * self.reverse

        if poi:
            start_pos = (xplacement + width / 2, yplacement + height / 2, state.zpos + z11)
            a, b, c = ( float(e - s) for s, e in zip(start_pos, poi) )

            #cameras is rotated in z, y, x order.
            #It is because rotating stage in x, y, z order means rotating a camera in z, y, x order.
            #rotating around z axis isn't rotating around the center of the screen when rotating camera in x, y, z order.
            v_len = math.sqrt(a**2 + b**2 + c**2) # math.hypot is better in py3.8+
            if v_len == 0:
                xpoi = ypoi = zpoi = 0
            else:
                a /= v_len
                b /= v_len
                c /= v_len

                sin_ypoi = min(1., max(-a, -1.))
                ypoi = math.asin(sin_ypoi)
                if c == 0:
                    if abs(a) == 1:
                        xpoi = 0
                    else:
                        sin_xpoi = min(1., max(b / math.cos(ypoi), -1.))
                        xpoi = math.asin(sin_xpoi)
                else:
                    xpoi = math.atan(-b/c)

                if c > 0:
                    ypoi = math.pi - ypoi

                if xpoi != 0.0 and ypoi != 0.0:
                    if xpoi == math.pi / 2 or xpoi == - math.pi / 2:
                        if -math.sin(xpoi) * math.sin(ypoi) > 0.0:
                            zpoi = math.pi / 2
                        else:
                            zpoi = - math.pi / 2
                    else:
                        zpoi = math.atan(-(math.sin(xpoi) * math.sin(ypoi)) / math.cos(xpoi))
                else:
                    zpoi = 0

                xpoi = math.degrees(xpoi)
                ypoi = math.degrees(ypoi)
                zpoi = math.degrees(zpoi)

        if poi or orientation or xyz_rotate:
            m = Matrix.offset(-width / 2, -height / 2, -z11)
        if poi:
            m = Matrix.rotate(-xpoi, -ypoi, -zpoi) * m
        if orientation:
            m = Matrix.rotate(-xorientation, -yorientation, -zorientation) * m
        if xyz_rotate:
            m = Matrix.rotate(-xrotate, -yrotate, -zrotate) * m
        if poi or orientation or xyz_rotate:
            m = Matrix.offset(width / 2, height / 2, z11) * m

            self.reverse = m * self.reverse

        if rotate is not None:
            m = Matrix.offset(-width / 2, -height / 2, 0.0)
            m = Matrix.rotate(0, 0, -rotate) * m
            m = Matrix.offset(width / 2, height / 2, 0.0) * m

            self.reverse = m * self.reverse

    else:

        if poi or orientation or xyz_rotate:
            if state.matrixanchor is None:

                manchorx = width / 2.0
                manchory = height / 2.0

            else:
                manchorx, manchory = state.matrixanchor

                if type(manchorx) is float:
                    manchorx *= width
                if type(manchory) is float:
                    manchory *= height

            m = Matrix.offset(-manchorx, -manchory, 0.0)

        if poi:
            placement = self.get_placement()
            xplacement, yplacement = renpy.display.core.place(widtho, heighto, width, height, placement)
            start_pos = (xplacement + manchorx, yplacement + manchory, state.zpos)

            a, b, c = ( float(e - s) for s, e in zip(start_pos, poi) )
            v_len = math.sqrt(a**2 + b**2 + c**2) # math.hypot is better in py3.8+
            if v_len == 0:
                xpoi = ypoi = 0
            else:
                a /= v_len
                b /= v_len
                c /= v_len

                sin_xpoi = min(1., max(-b, -1.))
                xpoi = math.asin(sin_xpoi)
                if c == 0:
                    if abs(b) == 1:
                        ypoi = 0
                    else:
                        sin_ypoi = min(1., max(a / math.cos(xpoi), -1.))
                        ypoi = math.asin(sin_ypoi)
                else:
                    ypoi = math.atan(a/c)

                if c < 0:
                    ypoi += math.pi

                xpoi = math.degrees(xpoi)
                ypoi = math.degrees(ypoi)

        if poi:
            m = Matrix.rotate(xpoi, ypoi, 0) * m
        if orientation:
            m = Matrix.rotate(xorientation, yorientation, zorientation) * m
        if xyz_rotate:
            m = Matrix.rotate(xrotate, yrotate, zrotate) * m
        if poi or orientation or xyz_rotate:
            m = Matrix.offset(manchorx, manchory, 0.0) * m

            self.reverse = m * self.reverse

        if state.zpos:
            self.reverse = Matrix.offset(0, 0, state.zpos) * self.reverse

    mt = state.matrixtransform

    # matrixtransform
    if mt is not None:

        if callable(mt):
            mt = mt(None, 1.0)

        if not isinstance(mt, renpy.display.matrix.Matrix):
            raise Exception("matrixtransform requires a Matrix (got %r)" % (mt,))

        if state.matrixanchor is None:

            manchorx = width / 2.0
            manchory = height / 2.0

        else:
            manchorx, manchory = state.matrixanchor

            if type(manchorx) is float:
                manchorx *= width
            if type(manchory) is float:
                manchory *= height

        m = Matrix.offset(-manchorx, -manchory, 0.0)
        m = mt * m
        m = Matrix.offset(manchorx, manchory, 0.0) * m

        self.reverse = m * self.reverse

    if state.zzoom and z11:
        zzoom = (z11 - state.zpos) / z11

        m = Matrix.offset(-width / 2, -height / 2, 0.0)
        m = Matrix.scale(zzoom, zzoom, 1) * m
        m = Matrix.offset(width / 2, height / 2, 0.0) * m

        self.reverse = m * self.reverse

    # perspective
    if perspective:
        near, z11, far = perspective
        self.reverse = Matrix.perspective(width, height, near, z11, far) * self.reverse

    # Set the forward matrix.
    if self.reverse is not IDENTITY:
        rv.reverse = self.reverse
        self.forward = rv.forward = self.reverse.inverse()
    else:
        self.forward = IDENTITY

    pos = (xo, yo)

    if state.subpixel:
        rv.subpixel_blit(cr, pos)
    else:
        rv.blit(cr, pos)

    if mesh and perspective:
        mr = rv = make_mesh(rv, state)

    # Nearest neighbor.
    rv.nearest = state.nearest

    if state.nearest:
        rv.add_property("texture_scaling", "nearest")

    if state.blend:
        rv.add_property("blend_func", renpy.config.gl_blend_func[state.blend])

    # Alpha.
    alpha = state.alpha

    if alpha < 0.0:
        alpha = 0.0
    elif alpha > 1.0:
        alpha = 1.0

    rv.alpha = alpha
    rv.over = 1.0 - state.additive

    if (rv.alpha != 1.0) or (rv.over != 1.0):
        rv.add_shader("renpy.alpha")
        rv.add_uniform("u_renpy_alpha", rv.alpha)
        rv.add_uniform("u_renpy_over", rv.over)

    # Shaders and uniforms.
    if state.shader is not None:

        if isinstance(state.shader, basestring):
            rv.add_shader(state.shader)
        else:
            for name in state.shader:
                rv.add_shader(name)

    for name in renpy.display.transform.uniforms:
        value = getattr(state, name, None)

        if value is not None:
            rv.add_uniform(name, value)

    for name in renpy.display.transform.gl_properties:
        value = getattr(state, name, None)

        if value is not None:
            if mesh:
                mr.add_property(name[3:], value)
            else:
                rv.add_property(name[3:], value)

    # Clipping.
    rv.xclipping = clipping
    rv.yclipping = clipping

    self.offsets = [ pos ]
    self.render_size = (width, height)

    return rv
